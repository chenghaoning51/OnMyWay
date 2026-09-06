#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""health.py — 阶段 4.2 巡检器（blog-health.timer 每 5 min 拉起；安装到 /srv/blog/bin/health.py）。

维度（plan 4.2）：站点不可达（nginx 层 /healthz-nginx 经 80 + API 层 /healthz 直连 8000）、
磁盘 > 85%、内存 MemAvailable/Total < 10%、证书 < 30 天、域名/ECS 到期 < 15 天。
部署失败不在此处：deploy.sh 的 alert() 经 /usr/local/bin/blog-alert 即时发信。

去抖：状态存 /srv/blog/state/health.json，每类目**连续 2 次失败**才发信（发过即静默），
恢复时发一封恢复通知并清零。退出码：0 全正常 ｜ 1 有失败（无论是否发信）。
"""

import json
import os
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import date, datetime

STATE_PATH = '/srv/blog/state/health.json'
CERT_PEM = '/etc/letsencrypt/live/tuanzi-wow.cn/fullchain.pem'
DOMAIN_EXPIRE = date(2027, 9, 4)   # plan §0.2 K12：两个到期日写死进阈值
ECS_EXPIRE = date(2028, 1, 13)
FAILS_BEFORE_ALERT = 2
DISK_MAX, MEM_MIN, CERT_DAYS, EXPIRE_DAYS = 0.85, 0.10, 30, 15
POLL_STALL_MAX = 15 * 60      # 更新链路停摆容忍窗：deploy.sh 写状态，此处按时间裁决（D37）
BACKUP_MAX_AGE = 26 * 3600    # 备份新鲜度：每日 03:30 一轮，超 26h 判陈旧
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))   # 本机探测不吃任何代理


def http_ok(url, host=None, timeout=8):
    req = urllib.request.Request(url, headers={'Host': host} if host else {},
                                 method='GET')
    try:
        with OPENER.open(req, timeout=timeout) as r:
            return r.status == 200
    except Exception:
        return False


def check_site():
    nginx_ok = http_ok('http://127.0.0.1/healthz-nginx', host='tuanzi-wow.cn')
    api_ok = http_ok('http://127.0.0.1:8000/healthz')
    ok = nginx_ok and api_ok
    return ok, 'nginx层=%s api层=%s' % ('ok' if nginx_ok else 'FAIL', 'ok' if api_ok else 'FAIL')


def check_disk():
    st = os.statvfs('/')
    used = st.f_blocks - st.f_bfree
    ratio = used / (used + st.f_bavail) if (used + st.f_bavail) else 1.0   # 与 df 的 Use% 同口径
    ok = ratio <= DISK_MAX
    return ok, '根分区已用 %.1f%% (阈值 %.0f%%)' % (ratio * 100, DISK_MAX * 100)


def check_mem():
    info = {}
    with open('/proc/meminfo', encoding='ascii') as f:
        for line in f:
            k, _, v = line.partition(':')
            info[k] = int(v.strip().split()[0])
    total, avail = info.get('MemTotal', 0), info.get('MemAvailable', 0)
    ok = total > 0 and (avail / total) >= MEM_MIN
    return ok, 'MemAvailable %dM / %dM (%.1f%%，阈值 ≥%.0f%%)' % (
        avail // 1024, total // 1024, avail / total * 100 if total else 0, MEM_MIN * 100)


def check_cert():
    try:
        out = subprocess.run(['openssl', 'x509', '-enddate', '-noout', '-in', CERT_PEM],
                             capture_output=True, text=True, timeout=10).stdout
        not_after = datetime.strptime(out.strip().split('=', 1)[1], '%b %d %H:%M:%S %Y %Z').date()
        days = (not_after - date.today()).days
        return days >= CERT_DAYS, '证书剩 %d 天（%s，阈值 ≥%d）' % (days, not_after, CERT_DAYS)
    except Exception as e:
        return False, '证书读取失败：%s: %s' % (type(e).__name__, str(e)[:80])


def check_expiry():
    today = date.today()
    d_days = (DOMAIN_EXPIRE - today).days
    e_days = (ECS_EXPIRE - today).days
    ok = d_days >= EXPIRE_DAYS and e_days >= EXPIRE_DAYS
    return ok, '域名剩 %d 天 / ECS 剩 %d 天（阈值 ≥%d）' % (d_days, e_days, EXPIRE_DAYS)


def _read_epoch(path):
    try:
        with open(path) as f:
            return float(f.read().strip())
    except Exception:
        return 0.0


def check_update():
    """更新链路停摆：deploy.sh --poll 失败时写 .poll-fails/.poll-fail-since（D37）。
    只按「首次失败距今时长」裁决——计数在边缘抖动下无意义，时间窗才代表真停摆。"""
    fails = int(_read_epoch('/srv/blog/state/.poll-fails') or 0)
    if fails <= 0:
        return True, '更新链路正常'
    stall = time.time() - _read_epoch('/srv/blog/state/.poll-fail-since')
    if stall < POLL_STALL_MAX:
        return True, '累计失败 %d 次（停摆 %d 分钟，容忍窗 <%d 分钟）' % (
            fails, stall // 60, POLL_STALL_MAX // 60)
    return False, '更新链路停摆 %d 分钟（连续失败 %d 次，阈值 <%d 分钟）' % (
        stall // 60, fails, POLL_STALL_MAX // 60)


def check_backup():
    """备份新鲜度：backup.sh 成功写 .backup-last-ok、失败写 .backup-last-fail。
    失败且未成功 → 即时判 FAIL（不必等 26h）；超 26h 无成功 → FAIL（陈旧）。"""
    ok_t = _read_epoch('/srv/blog/state/.backup-last-ok')
    fail_t = _read_epoch('/srv/blog/state/.backup-last-fail')
    if ok_t == 0:
        return False, '从未记录过成功备份'
    age_h = (time.time() - ok_t) / 3600
    if fail_t > ok_t:
        return False, '最近一次备份失败于 %.1f 小时前（成功是 %.1f 小时前，阈值 <%.0fh）' % (
            (time.time() - fail_t) / 3600, age_h, BACKUP_MAX_AGE / 3600)
    ok = age_h <= BACKUP_MAX_AGE / 3600
    return ok, '最近成功备份 %.1f 小时前（阈值 <%.0fh）' % (age_h, BACKUP_MAX_AGE / 3600)


CHECKS = [('site', check_site), ('disk', check_disk), ('mem', check_mem),
          ('cert', check_cert), ('expiry', check_expiry),
          ('update', check_update), ('backup', check_backup)]


def load_state():
    try:
        with open(STATE_PATH, encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return {'fails': {}, 'alerted': {}}


def save_state(st):
    tmp = STATE_PATH + '.tmp'
    os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(st, f, ensure_ascii=False)
    os.replace(tmp, STATE_PATH)


def main():
    results, failed = [], {}
    for name, fn in CHECKS:
        try:
            ok, detail = fn()
        except Exception as e:
            ok, detail = False, '%s: %s' % (type(e).__name__, str(e)[:80])
        results.append((name, ok, detail))
        if not ok:
            failed[name] = detail

    st = load_state()
    fails, alerted = st.setdefault('fails', {}), st.setdefault('alerted', {})
    now = datetime.now().isoformat(timespec='seconds')

    to_alert = []
    for name, ok, detail in results:
        if ok:
            fails[name] = 0
            if alerted.get(name):
                alerted[name] = False
                to_alert.append('%s 已恢复：%s' % (name, detail))
        else:
            fails[name] = fails.get(name, 0) + 1
            if fails[name] >= FAILS_BEFORE_ALERT and not alerted.get(name):
                alerted[name] = True
                to_alert.append('%s 连续 %d 次失败：%s' % (name, fails[name], detail))

    save_state(st)
    for name, ok, detail in results:
        print('[%s] %-7s %s' % ('OK ' if ok else 'FAIL', name, detail))

    if to_alert:
        subject = '巡检告警' if failed else '巡检恢复'
        body = 'blog 巡检 @%s\n%s' % (now, '\n'.join(to_alert))
        try:
            p = subprocess.run(['/usr/local/bin/blog-alert', subject], input=body,
                               text=True, capture_output=True, timeout=90)
            print('邮件发送 rc=%s（%d 条：%s）' % (p.returncode, len(to_alert), '；'.join(failed) or '恢复'))
        except Exception as e:
            print('邮件发送异常：%s: %s' % (type(e).__name__, str(e)[:80]))
    elif failed:
        print('有失败但未达告警阈值或已告警过（连续 %d 次才发，发过即静默）' % FAILS_BEFORE_ALERT)
    else:
        print('全部正常')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
