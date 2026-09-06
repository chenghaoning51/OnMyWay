#!/usr/bin/env bash
# install-stage4.sh — 阶段 4「运维闭环」的服务端安装 + 自检（幂等，可反复执行）
#
# 在 Workbench 里以 root 执行（本文件随仓库走，本地改完 push，服务器上重跑一次即可）：
#     bash /srv/blog/src/deploy/install-stage4.sh
# 开关：
#     --test-alert   用已填好的 /etc/blog/blog-alert.env 发一封测试邮件（验收 4.3）
#
# 铁律：只新增与替换；凭据模板只建不覆盖（REPLACE_ME 检测），不打印任何凭据值。
# 输出全部是可回传的判据行（[OK]/[FAIL]/[NOTE] + 数字）。
set -uo pipefail

REPO=${REPO:-/srv/blog/src}
BIN=${BIN:-/srv/blog/bin}
ETC=${ETC:-/etc/blog}
STATE=${STATE:-/srv/blog/state}
BK=/root/stage4-backup/$(date +%Y%m%d-%H%M%S)
PASS=0; FAIL=0; NOTE=0
sec()  { printf '\n########## %s ##########\n' "$*"; }
ck()   { if [ "$2" = 0 ]; then PASS=$((PASS+1)); printf '[OK]   %s ｜ %s\n' "$1" "${3:-}"; else FAIL=$((FAIL+1)); printf '[FAIL] %s ｜ %s\n' "$1" "${3:-}"; fi; }
note() { NOTE=$((NOTE+1)); printf '[NOTE] %s ｜ %s\n' "$1" "${2:-}"; }

if [ "$(id -u)" != 0 ]; then echo '须以 root 运行' >&2; exit 5; fi

case "${1:-}" in
  --test-alert)
    if grep -q 'REPLACE_ME' "$ETC/blog-alert.env" 2>/dev/null; then
      echo "$ETC/blog-alert.env 里还有 REPLACE_ME：填 QQ 邮箱与授权码（SMTP_PASS）后重跑 --test-alert" >&2; exit 7
    fi
    printf '这是一封来自 %s 的阶段 4.3 测试邮件。收到即告警链路（QQ SMTP 465/SSL）验收通过。\n' "$(hostname)"
    /usr/local/bin/blog-alert '阶段 4.3 测试邮件：告警链路已通'; rc=$?
    [ "$rc" = 0 ]; ck '测试邮件发送' "$?" "rc=$rc（去 QQ 邮箱确认收到，防垃圾箱）"
    exit "$rc"
    ;;
  '') : ;;
  *) printf '未知参数：%s（可用：--test-alert）\n' "$1" >&2; exit 4 ;;
esac

# 防「自己改写自己」（与 stage2/3 同款）
case "$0" in
  "$REPO"/*)
    if cp -f "$0" /tmp/blog-stage4-install.sh && chmod 0700 /tmp/blog-stage4-install.sh; then
      exec bash /tmp/blog-stage4-install.sh "$@"
    fi
    echo '警告：本脚本没能复制到 /tmp，将继续就地执行' >&2
    ;;
esac

sec 'P0 前置实况'
printf '本脚本 sha256=%s\n' "$(sha256sum "$0" | cut -c1-16)"
printf '仓库 HEAD=%s ｜ python=%s ｜ 内存 %s ｜ 磁盘 %s\n' \
  "$(sudo -u blog git -C "$REPO" rev-parse --short HEAD 2>/dev/null)" "$(python3 -V 2>&1)" \
  "$(free -m | awk '/^Mem:/{print "used "$3"M / avail "$7"M"}')" "$(df -h / | awk 'NR==2{print $3"/"$2" ("$5")"}')"
mkdir -p "$BK" && chmod 700 "$BK"
printf '备份目录=%s\n' "$BK"

sec 'P1 仓库文件与语法体检'
for f in scripts/blog-alert.py scripts/health.py scripts/backup.sh deploy/systemd/blog-backup.service deploy/systemd/blog-backup.timer deploy/systemd/blog-health.service deploy/systemd/blog-health.timer deploy/logrotate/blog; do
  if [ -f "$REPO/$f" ]; then PASS=$((PASS+1)); printf '[OK]   存在 %s\n' "$f"; else ck "存在 $f" 1 '仓库里没有这个文件'; fi
done
CRLF=$(grep -rlI $'\r' "$REPO/scripts" "$REPO/deploy" 2>/dev/null | tr '\n' ' ')
if [ -z "$CRLF" ]; then ck '仓库换行符体检' 0 'scripts/ 与 deploy/ 全部 LF'; else ck '仓库换行符体检' 1 "检出 CR：$CRLF"; exit 8; fi
for f in scripts/blog-alert.py scripts/health.py; do
  /usr/bin/python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' "$REPO/$f" 2> "$BK/pyc.log"
  ck "py 语法 $f" "$?" "$(tail -c 160 "$BK/pyc.log")"
done
bash -n "$REPO/scripts/backup.sh" 2> "$BK/bashn.log"; ck 'backup.sh 语法' "$?" "$(cat "$BK/bashn.log")"

sec 'P2 安装（root 持有 0755/0644，与 stage2 的 bin 权限模型一致）'
install -m 0755 -o root -g root "$REPO/scripts/blog-alert.py" /usr/local/bin/blog-alert
ck 'blog-alert → /usr/local/bin' "$([ -x /usr/local/bin/blog-alert ] && echo 0 || echo 1)" "deploy.sh 的 alert() 即刻生效（阶段 2 预留的调用点）"
mkdir -p "$BIN"
install -m 0755 -o root -g root "$REPO/scripts/health.py" "$BIN/health.py"
install -m 0755 -o root -g root "$REPO/scripts/backup.sh" "$BIN/backup.sh"
ck 'health.py / backup.sh → /srv/blog/bin' "$([ -x "$BIN/health.py" ] && [ -x "$BIN/backup.sh" ] && echo 0 || echo 1)"
install -m 0644 -o root -g root "$REPO/deploy/logrotate/blog" /etc/logrotate.d/blog
ck 'logrotate 配置' "$([ -f /etc/logrotate.d/blog ] && echo 0 || echo 1)" '/srv/blog/logs/*.log 按天 14 份 copytruncate'
logrotate -d /etc/logrotate.d/blog > "$BK/lr-dry.log" 2>&1
# D33：grep -q 找到错误时 rc=0、没有时 rc=1——判据必须正向断言「无错误」，不能把 rc 直接喂给 ck
if grep -qiE '^error' "$BK/lr-dry.log"; then
  ck 'logrotate 语法（dry-run）' 1 "$(grep -iE '^error' "$BK/lr-dry.log" | head -2 | tr '\n' ' ')"
else
  ck 'logrotate 语法（dry-run）' 0 "错误行数=$(grep -ciE '^error' "$BK/lr-dry.log")"
fi
if [ -f /etc/logrotate.d/nginx ]; then
  note 'nginx 日志轮转' "系统包自带（$(grep -m1 'rotate ' /etc/logrotate.d/nginx | tr -s ' ')），/var/log/nginx/*.log 已被覆盖，不重复配"
else
  note 'nginx 日志轮转' '/etc/logrotate.d/nginx 不存在，nginx 日志无轮转——回传此行定性'
fi
for u in blog-backup.service blog-backup.timer blog-health.service blog-health.timer; do
  install -m 0644 -o root -g root "$REPO/deploy/systemd/$u" "/etc/systemd/system/$u"
done
systemd-analyze verify /etc/systemd/system/blog-backup.{service,timer} /etc/systemd/system/blog-health.{service,timer} > "$BK/unit-verify.log" 2>&1
note 'systemd-analyze verify' "$(wc -l < "$BK/unit-verify.log") 行提示（snapd 噪音可忽略）：$(head -c 200 "$BK/unit-verify.log" | tr '\n' ' ')"
systemctl daemon-reload; ck 'daemon-reload' "$?"

sec 'P3 凭据位（只建不覆盖；REPLACE_ME 由你在服务器上填）'
if [ ! -s "$ETC/blog-alert.env" ]; then
  printf '# 告警凭据（0600）。SMTP_PASS 填 QQ 邮箱「授权码」——设置→账号→开启 SMTP 服务后生成，不是登录密码\nMAIL_FROM=REPLACE_ME\nMAIL_TO=REPLACE_ME\nSMTP_USER=REPLACE_ME\nSMTP_PASS=REPLACE_ME\n' > "$ETC/blog-alert.env"
fi
chown root:root "$ETC/blog-alert.env"; chmod 0600 "$ETC/blog-alert.env"
grep -q 'REPLACE_ME' "$ETC/blog-alert.env"; NEED_ALERT=$?
[ "$NEED_ALERT" = 0 ] && note 'blog-alert.env' "已放模板（0600），填 QQ 邮箱与授权码后跑 --test-alert" || ck 'blog-alert.env 已填' 0
if [ ! -s "$ETC/backup-git.env" ]; then
  printf '# 备份推送凭据（0600）。在 GitHub 建私有空仓库 blog-backup，并造 fine-grained PAT（只授该仓库 Contents: Read and write）\n# BACKUP_REPO_URL 形如：https://<GitHub用户名>:<PAT>@github.com/<GitHub用户名>/blog-backup.git\nBACKUP_REPO_URL=REPLACE_ME\n' > "$ETC/backup-git.env"
fi
chown root:root "$ETC/backup-git.env"; chmod 0600 "$ETC/backup-git.env"
grep -q 'REPLACE_ME' "$ETC/backup-git.env"; NEED_BACKUP=$?
[ "$NEED_BACKUP" = 0 ] && note 'backup-git.env' "已放模板（0600），建好私有仓库并填 URL 后重跑本脚本" || ck 'backup-git.env 已填' 0
ls -l "$ETC"/blog-alert.env "$ETC"/backup-git.env | awk '{print "  " $1, $3":"$4, $9}'

sec 'P4 timers 装载（enable --now：enable 只建链接不启动，D26）'
systemctl enable --now blog-health.timer blog-backup.timer > "$BK/enable.log" 2>&1
ck 'enable --now health+backup timers' "$?" "$(tr '\n' ' ' < "$BK/enable.log" | head -c 120)"
for t in blog-health.timer blog-backup.timer; do
  NEXT=$(systemctl list-timers --no-legend "$t" 2>/dev/null | awk '{print $2, $3}')
  [ -n "$NEXT" ]; ck "$t 已激活" "$?" "is-active=$(systemctl is-active "$t" 2>&1) 下次=$NEXT（OnUnitActiveSec 型首跑前可能显示 n/a，见下一条 service 首跑判据）"
done
# OnUnitActiveSec 型 timer 未首跑时 list-timers 的 NEXT 显示 n/a —— 主动跑一次 service 路径（ConditionPathExists+ExecStart 全链路）
systemctl start blog-health.service 2> /dev/null; sleep 1
journalctl -u blog-health.service -n 6 --no-pager -o short-iso 2>/dev/null | sed 's/^/  /'
ck 'blog-health.service 首跑' "$([ "$(systemctl show -p Result --value blog-health.service 2>/dev/null)" = success ] && echo 0 || echo 1)" "Result=$(systemctl show -p Result --value blog-health.service 2>/dev/null)"
# 备份本轮真实跑一遍并查终态（D34：子进程的 [FAIL] 必须进顶层计数，不能只展示）。
# 用 --no-block + 进度轮询：push 重试最坏 ~5 min，阻塞式 restart 会让 Workbench 像死机（首跑实证）；
# systemd TimeoutStartSec=600 兜底，轮询上限 480s
systemctl restart --no-block blog-backup.service 2> /dev/null
ST=$(systemctl show -p ActiveState --value blog-backup.service 2>/dev/null)
WAITED=0
while [ "$ST" = activating ] && [ "$WAITED" -lt 720 ]; do
  sleep 15; WAITED=$((WAITED + 15))
  printf '  等待备份完成 %ds（push 重试最坏 ~7 min，GitHub 间歇不可达时自动重试 5 次）...\n' "$WAITED"
  ST=$(systemctl show -p ActiveState --value blog-backup.service 2>/dev/null)
done
RES=$(systemctl show -p Result --value blog-backup.service 2>/dev/null)
ck 'blog-backup.service 本轮备份' "$([ "$ST" = inactive ] && [ "$RES" = success ] && echo 0 || echo 1)" "ActiveState=$ST Result=$RES（FAIL 时看上方 journalctl，多为 GitHub 直连间歇超时，重跑即可）"
sleep 1

sec 'P5 端到端自检（巡检 + 备份真实各跑一轮）'
if /usr/bin/python3 "$BIN/health.py"; then HRC=0; else HRC=1; fi
ck 'health.py 巡检' "$([ "$HRC" = 0 ] && echo 0 || echo 1)" "rc=$HRC（首跑有失败属连续计数第 1 次，不发信；凭据未填时即使到达阈值也只 NOTE）"
[ -s "$STATE/health.json" ]; ck '巡检状态文件' "$?" "$(cat "$STATE/health.json" 2>/dev/null | head -c 120)"
journalctl -u blog-backup.service -n 12 --no-pager -o short-iso 2>/dev/null | sed 's/^/  /'
if [ "$NEED_BACKUP" = 0 ]; then
  note '备份私有仓库' 'URL 未配置，本轮仅本地备份；填好 backup-git.env 后重跑本脚本以验证 push'
fi
printf '\n下一步（人做的）：\n'
printf '  1) QQ 邮箱授权码填入 %s/blog-alert.env（四行全填），然后：\n     bash %s/deploy/install-stage4.sh --test-alert\n     收到邮件即 4.3 验收通过\n' "$ETC" "$REPO"
printf '  2) GitHub 建私有空仓库 blog-backup，造 fine-grained PAT（只授该仓库 Contents: Read and write），\n     URL 填入 %s/backup-git.env，重跑本脚本——判据看「私有仓库快照 push 成功」\n' "$ETC"
printf '  3) 告警验收（4.2）：systemctl stop blog-api → 等 10~15 min 收到「site 连续 2 次失败」邮件 → systemctl start blog-api →\n     再等 5 min 收到「已恢复」邮件\n'
printf '  4) 择期按 docs/runbook.md 做一次整站重建演练（4.5 验收）\n'
printf '\nSTAGE4-DONE pass=%s fail=%s note=%s\n' "$PASS" "$FAIL" "$NOTE"
exit 0
