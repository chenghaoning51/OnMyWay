#!/usr/bin/env bash
# backup.sh — 阶段 4.1 每日备份（blog-backup.timer 03:30 拉起；安装到 /srv/blog/bin/backup.sh，root 运行）
#
# 流程（plan 4.1，2026-09-06 设计定稿）：
#   1) git bundle --all（blog 身份避开 dubious ownership）  2) 配置/证书 tar（含 letsencrypt 私钥，包 0600）
#   3) Python sqlite3.backup() 备 DB + integrity_check      4) /srv/blog/backup 滚动保留 14 天（0700）
#   5) 整目录单提交 force-push 成私有仓库快照（仓库恒为最新快照；BACKUP_REPO_URL 内含 PAT）
# 私有仓库未配置（REPLACE_ME）时：本地四步照跑，push 跳过并 [NOTE]。任何 FAIL 都以非零退出，
# systemd 视为失败；push 失败额外调 /usr/local/bin/blog-alert（存在才调）。
set -uo pipefail

BASE=${BASE:-/srv/blog}
BAK=$BASE/backup
SRC=$BASE/src
DATA=$BASE/data
STATE=$BASE/state
KEEP=${KEEP:-14}
ENV_FILE=${ENV_FILE:-/etc/blog/backup-git.env}
TS=$(date +%Y%m%d-%H%M%S)
FAILED=0
ok()   { printf '[OK]   %s ｜ %s\n' "$1" "${2:-}"; }
fail() { printf '[FAIL] %s ｜ %s\n' "$1" "${2:-}"; FAILED=$((FAILED+1)); }
note() { printf '[NOTE] %s ｜ %s\n' "$1" "${2:-}"; }
finish() {
  logger -t blog-backup "rc=$FAILED$1 ts=$TS" 2>/dev/null
  if [ "$FAILED" -gt 0 ] && [ -x /usr/local/bin/blog-alert ]; then
    /usr/local/bin/blog-alert "每日备份有 $FAILED 项失败（详见 journalctl -u blog-backup）" >/dev/null 2>&1
  fi
  exit $(( FAILED > 0 ? 1 : 0 ))
}
[ "$(id -u)" = 0 ] || { echo '须以 root 运行' >&2; exit 5; }
mkdir -p "$BAK"; chmod 0700 "$BAK"

# 1) git bundle --all（含全部历史；blog 身份跑 git，仓库属它）
if sudo -u blog git -C "$SRC" bundle create "/tmp/repo-$TS.bundle" --all > /tmp/backup-bundle.log 2>&1; then
  mv -f "/tmp/repo-$TS.bundle" "$BAK/repo-$TS.bundle"
  ok 'git bundle' "大小=$(du -h "$BAK/repo-$TS.bundle" | cut -f1)"
else
  fail 'git bundle' "$(tail -c 160 /tmp/backup-bundle.log | tr '\n' ' ')"
fi

# 2) 配置与证书 tar（还原 = 解回 / 即恢复站点配置；含 letsencrypt 私钥，故包 0600 且目录 0700）
if tar -C / -czf "$BAK/etc-$TS.tar.gz" \
     etc/blog etc/nginx etc/letsencrypt etc/logrotate.d/blog \
     etc/systemd/system/blog-backup.service etc/systemd/system/blog-backup.timer \
     etc/systemd/system/blog-health.service etc/systemd/system/blog-health.timer \
     etc/systemd/system/blog-api.service etc/systemd/system/blog-poll.service \
     etc/systemd/system/blog-poll.timer etc/systemd/system/blog-deploy-hook.service \
     etc/systemd/system/blog-certbot-renew.service etc/systemd/system/blog-certbot-renew.timer \
     2> /tmp/backup-tar.log; then
  chmod 0600 "$BAK/etc-$TS.tar.gz"
  ok '配置/证书 tar' "大小=$(du -h "$BAK/etc-$TS.tar.gz" | cut -f1)（含 letsencrypt 私钥，0600）"
else
  fail '配置/证书 tar' "$(tail -c 160 /tmp/backup-tar.log | tr '\n' ' ')"
fi

# 3) DB 备份（sqlite3.backup API 在线一致性快照）+ 完整性自证
DBINFO=$(/usr/bin/python3 - "$DATA/search.db" "$BAK/search-$TS.db" <<'PYEOF'
import sqlite3, sys
src, dst = sys.argv[1], sys.argv[2]
s = sqlite3.connect(src)
d = sqlite3.connect(dst)
with d:
    s.backup(d)
d.close(); s.close()
c = sqlite3.connect(dst)
ok = c.execute('PRAGMA integrity_check').fetchone()[0]
n = c.execute('SELECT COUNT(*) FROM posts').fetchone()[0]
v = c.execute('SELECT COUNT(*) FROM visit').fetchone()[0]
c.close()
print('integrity=%s posts=%d visit_rows=%d 大小=%dKB' % (ok, n, v, __import__('os').path.getsize(dst) // 1024))
sys.exit(0 if ok == 'ok' else 1)
PYEOF
)
if [ "$?" = 0 ]; then
  ok 'DB 备份' "$DBINFO"
else
  fail 'DB 备份' "${DBINFO:-integrity_check 未过或 backup 失败}"
fi

# 4) 滚动保留 14 天（三类文件各按名字精确匹配，不误删）
DELETED=$(find "$BAK" -maxdepth 1 -type f \( -name 'repo-*.bundle' -o -name 'etc-*.tar.gz' -o -name 'search-*.db' \) -mtime +"$KEEP" -delete -print | wc -l)
ok '本地滚动清理' "删除 ${DELETED} 个 >${KEEP} 天的旧备份；现留 $(ls -1 "$BAK" | wc -l) 个文件"

# 5) force-push 快照到私有仓库（整目录 = 单提交快照，仓库体积恒定）
[ -r "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }
case "${BACKUP_REPO_URL:-}" in
  https://*@github.com/*) : ;;
  *) note '私有仓库未配置' "在 $ENV_FILE 填 BACKUP_REPO_URL（形如 https://<PAT>@github.com/<user>/blog-backup.git）后重跑；本次本地备份已完成且可用"; finish " local-only"; ;;
esac
WORK=$(mktemp -d)
if git init -q -b main "$WORK" \
   && find "$BAK" -maxdepth 1 -type f -exec cp -p {} "$WORK/" \; \
   && git -C "$WORK" add -A \
   && git -C "$WORK" -c user.name=blog-backup -c user.email=blog-backup@localhost commit -qm "backup $TS"; then
  # 到 GitHub:443 间歇不可达（同 deploy.sh 的已知症状：connect 130s 超时等），复用其对策：HTTP/1.1 + 退避重试
  PUSH_OK=0; TRIES=0
  for wait_s in 0 5 15; do
    TRIES=$((TRIES + 1))
    [ "$wait_s" -gt 0 ] && sleep "$wait_s"
    if timeout 90 git -C "$WORK" -c http.version=HTTP/1.1 push --force "$BACKUP_REPO_URL" main:main > /tmp/backup-push.log 2>&1; then
      PUSH_OK=1; break
    fi
  done
  if [ "$PUSH_OK" = 1 ]; then
    ok '私有仓库快照' "push 成功（第 ${TRIES} 次尝试｜快照含 $(ls -1 "$WORK" | grep -vc '^\.git') 个文件）"
  else
    fail '私有仓库快照' "3 次重试后仍失败：$(tail -c 160 /tmp/backup-push.log | tr '\r' ' ' | tr '\n' ' ')（本地 14 天滚动备份不受影响）"
  fi
else
  fail '私有仓库快照' "git init/commit 阶段失败：$(tail -c 160 /tmp/backup-push.log 2>/dev/null | tr '\r' ' ' | tr '\n' ' ')"
fi
rm -rf "$WORK"
finish ""
