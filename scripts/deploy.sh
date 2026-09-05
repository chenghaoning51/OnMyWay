#!/usr/bin/env bash
# deploy.sh — 阶段 2.1 发布脚本。固定顺序见 docs/plan.md §3.2（不可调换）。
#
# 用法：deploy.sh [--poll | --force | --rollback | --status]
#   无参数     完整走一遍链路；远端 sha 与已发布 sha 相同则直接退出
#   --poll     同上，但「无变化」时不写部署日志（供 blog-poll.timer 每 60 s 调用）
#   --force    即使 sha 相同也重新构建并切版（首次发布、改配置后用）
#   --rollback 软链切回上一个 release，不重新构建（回滚一条命令）
#   --status   打印当前版本、已发布 sha、release 列表
#
# 核心不变量：先建新 release，健全性检查通过才原子切软链；
#            任一步失败 → 线上继续服务旧内容（宁可旧，不可坏）。
# 权限模型：脚本本身以 root 运行，但 git 与 hugo 一律降权到 blog——
#            仓库内容属不可信输入，绝不用 root 解析。
# 退出码：0 成功或无需动作 ｜ 1 构建失败 ｜ 2 产物不健全/切链失败 ｜ 3 git 失败 ｜ 4 参数错 ｜ 5 非 root
set -uo pipefail

ENV_FILE=${ENV_FILE:-/etc/blog/deploy.env}
[ -r "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }

BASE=${BASE:-/srv/blog}
SRC=$BASE/src
REL=$BASE/releases
STATE=$BASE/state
LOGD=$BASE/logs
CURRENT=$BASE/current
LOCK=$BASE/.deploy.lock
KEEP=${KEEP:-5}                     # 保留最近 N 版可回滚
MIN_HTML=${MIN_HTML:-30}            # 产物 html 文件数下限（实测 75 页），低于即判构建异常
SITE_HOST=${SITE_HOST:-tuanzi-wow.cn}
BLOG_USER=${BLOG_USER:-blog}
PULL_HOST=${PULL_HOST:-origin}
PULL_REF=${PULL_REF:-main}
HUGO=${HUGO:-hugo}
REINDEX_URL=${REINDEX_URL:-http://127.0.0.1:8000/api/reindex}
REINDEX_TOKEN=${REINDEX_TOKEN:-}

MODE=deploy
case "${1:-}" in
  ''|deploy) MODE=deploy ;;
  --poll) MODE=poll ;;
  --force) MODE=force ;;
  --rollback) MODE=rollback ;;
  --status) MODE=status ;;
  *) printf '未知参数：%s（可用：--poll --force --rollback --status）\n' "$1" >&2; exit 4 ;;
esac

NOW() { date '+%F %T'; }
mkdir -p "$REL" "$STATE" "$LOGD"
log()   { printf '%s %s\n' "$(NOW)" "$*" >> "$LOGD/deploy.log"; command -v logger >/dev/null 2>&1 && logger -t blog-deploy -- "$*"; }
alert() { log "ALERT $*"; if [ -x /usr/local/bin/blog-alert ]; then /usr/local/bin/blog-alert "$*" >/dev/null 2>&1; fi; return 0; }
trim_log() { if [ -f "$LOGD/deploy.log" ] && [ "$(wc -l < "$LOGD/deploy.log")" -gt 2000 ]; then tail -n 1000 "$LOGD/deploy.log" > "$LOGD/.deploy.log.tmp" && mv -Tf "$LOGD/.deploy.log.tmp" "$LOGD/deploy.log"; fi; }

if [ "$(id -u)" != 0 ]; then echo '须以 root 运行（git/hugo 由脚本内部降权到 blog）' >&2; exit 5; fi
umask 022
BLOG_UID=$(id -u "$BLOG_USER") BLOG_GID=$(id -g "$BLOG_USER")
if command -v setpriv >/dev/null 2>&1; then
  as_blog() { setpriv --reuid "$BLOG_UID" --regid "$BLOG_GID" --clear-groups env -i HOME="$BASE" USER="$BLOG_USER" LOGNAME="$BLOG_USER" PATH=/usr/local/bin:/usr/bin:/bin "$@"; }
else
  as_blog() { runuser -u "$BLOG_USER" -- env HOME="$BASE" PATH=/usr/local/bin:/usr/bin:/bin "$@"; }
fi
reload_nginx() {
  if nginx -t >/dev/null 2>&1; then
    if systemctl reload nginx 2>> "$LOGD/deploy.log"; then log 'nginx reload ok'; else alert 'nginx reload 失败：软链已切，内容仍会更新，但需人工确认'; fi
  else
    alert 'nginx -t 失败（配置有问题，未 reload），立即人工检查 /etc/nginx'
  fi
}

if [ "$MODE" = status ]; then
  printf 'current  = %s\n' "$(readlink "$CURRENT" 2>/dev/null || echo '（无）')"
  printf 'sha      = %s\n' "$(cat "$STATE/deployed_sha" 2>/dev/null || echo '（无）')"
  printf 'last     = %s\n' "$(cat "$STATE/last-deploy" 2>/dev/null || echo '（无）')"
  printf 'poll     = %s\n' "$(cat "$STATE/last-poll" 2>/dev/null || echo '（无）')"
  printf 'releases = %s\n' "$(ls -1 "$REL" 2>/dev/null | sort -r | tr '\n' ' ')"
  exit 0
fi

if [ "$MODE" = rollback ]; then
  CUR=$(readlink -f "$CURRENT" 2>/dev/null || echo '')
  PREV=$(ls -1 "$REL" 2>/dev/null | sort -r | sed -n '2p')
  if [ -z "$PREV" ] || [ ! -s "$REL/$PREV/index.html" ]; then alert "回滚失败：没有可用的上一个 release（候选=$PREV）"; exit 2; fi
  ln -sfn "$REL/$PREV" "$BASE/.current.new" && mv -Tf "$BASE/.current.new" "$CURRENT" || { alert '回滚切链失败'; exit 2; }
  echo '' > "$STATE/deployed_sha"          # 清空 sha，让下一轮 poll 重新拉取真实内容
  reload_nginx
  log "已回滚 $(basename "$CUR") -> $PREV（deployed_sha 已清空，等待下次发布）"
  exit 0
fi

exec 9> "$LOCK" || exit 3
flock -n 9 || { log '已有发布在进行，跳过本次触发'; exit 0; }
T0=$(date +%s)
DEPLOYED=$(cat "$STATE/deployed_sha" 2>/dev/null || echo '')

# 1) 轻量探一次远端 sha（一次 HTTPS 请求，作为 --poll 的判据）
REMOTE=$(as_blog git -C "$SRC" ls-remote "$PULL_HOST" "heads/$PULL_REF" 2> "$STATE/.lsremote.err" | awk '{print $1}')
if [ -z "$REMOTE" ]; then
  alert "git ls-remote 失败（出网或权限），本次不动线上：$(tail -c 200 "$STATE/.lsremote.err" | tr -d '\r')"
  exit 3
fi
printf '%s remote=%s deployed=%s\n' "$(NOW)" "${REMOTE:0:7}" "${DEPLOYED:0:7}" > "$STATE/last-poll"
if [ "$REMOTE" = "$DEPLOYED" ]; then
  if [ "$MODE" = force ]; then log '--force：sha 未变仍重新发布'; else
    [ "$MODE" = poll ] || log "远端无新提交（sha=${DEPLOYED:0:7}），跳过"
    exit 0
  fi
fi

# 2) 拉取：首次把浅历史补全（hugo enableGitInfo 需要文件级提交时间），失败退避 2/5/10 s 重试 3 次
if [ -f "$SRC/.git/shallow" ]; then
  as_blog git -C "$SRC" fetch --unshallow "$PULL_HOST" "$PULL_REF" >> "$LOGD/deploy.log" 2>&1 || log 'unshallow 未成功（不影响后续 pull）'
fi
rc=1
for wait_s in 0 2 5 10; do
  [ "$wait_s" -gt 0 ] && sleep "$wait_s"
  if as_blog git -C "$SRC" pull --ff-only "$PULL_HOST" "$PULL_REF" >> "$LOGD/deploy.log" 2>&1; then rc=0; break; fi
done
if [ "$rc" != 0 ]; then alert 'git pull 失败（含 3 次退避重试），线上继续服务旧内容'; exit 3; fi
HEAD_SHA=$(as_blog git -C "$SRC" rev-parse HEAD)

# 3) 构建到全新 release（绝不就地覆盖线上目录）
TS=$(date +%Y%m%d-%H%M%S)
OUT=$REL/$TS
mkdir -p "$OUT" && chown "$BLOG_USER:$BLOG_USER" "$OUT"
BUILD_LOG=$LOGD/last-build.log
if ! as_blog "$HUGO" --source "$SRC" --destination "$OUT" --gc --minify --logLevel warn > "$BUILD_LOG" 2>&1; then
  alert "hugo 构建失败 sha=${HEAD_SHA:0:7}，未切版；见 $LOGD/last-build.log"
  rm -rf -- "$OUT"; trim_log; exit 1
fi
HTML_N=$(find "$OUT" -type f -name '*.html' | wc -l)

# 4) 产物健全性检查（坏 front matter / 空产物在这里被拦下）
if [ ! -s "$OUT/index.html" ]; then alert "产物缺 index.html，未切版"; rm -rf -- "$OUT"; trim_log; exit 2; fi
if [ "$HTML_N" -lt "$MIN_HTML" ]; then alert "产物 html 数 $HTML_N < 阈值 $MIN_HTML，疑似构建异常，未切版"; rm -rf -- "$OUT"; trim_log; exit 2; fi

# 5) 原子切软链（ln + mv -Tf：同一文件系统内的 rename，读者只会看到旧或新，不会看到空档）
PREV=$(readlink -f "$CURRENT" 2>/dev/null || echo '')
if ! ln -sfn "$OUT" "$BASE/.current.new" || ! mv -Tf "$BASE/.current.new" "$CURRENT"; then
  alert '切软链失败，线上保持旧版本'; exit 2
fi
chmod 0755 "$BASE" "$REL"
chmod -R a+rX "$OUT"                       # nginx 以 www-data 读产物，需目录 x + 文件 r

# 6) nginx（软链已切，nginx 逐请求解析路径，reload 只是清理旧配置）
reload_nginx
CODE=$(curl -s -o /dev/null -w '%{http_code}' -m 8 -H "Host: $SITE_HOST" http://127.0.0.1/ || echo 000)
[ "$CODE" = 200 ] || alert "本机 80 取 / 返回 $CODE（期望 200）"

# 7) 检索增量（阶段 3 未上线时静默跳过）
if curl -fsS -m 3 http://127.0.0.1:8000/healthz > /dev/null 2>&1; then
  if curl -fsS -m 60 -X POST -H "X-Reindex-Token: $REINDEX_TOKEN" "$REINDEX_URL" > /dev/null 2>&1; then
    log 'reindex ok'
  else
    alert 'POST /api/reindex 失败：检索索引落后于内容'
  fi
else
  log '127.0.0.1:8000 未监听（阶段 3 未上线），跳过 reindex'
fi

# 8) 记录状态
echo "$HEAD_SHA" > "$STATE/deployed_sha"
printf '%s sha=%s out=%s prev=%s selfcheck=%s\n' "$(NOW)" "$HEAD_SHA" "$OUT" "$(basename "$PREV")" "$CODE" > "$STATE/last-deploy"

# 9) 清理旧 release：保留最近 KEEP 版，current 指向的那版永不删
LIVE=$(readlink -f "$CURRENT" 2>/dev/null || echo '')
i=0
for d in $(ls -1 "$REL" 2>/dev/null | sort -r); do
  i=$((i + 1))
  [ "$i" -le "$KEEP" ] && continue
  case "$d" in
    20[0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9])
      [ "$REL/$d" = "$LIVE" ] && continue
      [ "$REL/$d" = "$OUT" ] && continue
      rm -rf -- "$REL/$d" && log "清理旧 release $d" ;;
  esac
done

log "发布完成 sha=${HEAD_SHA:0:7} html=$HTML_N 自检=$CODE 耗时=$(( $(date +%s) - T0 ))s"
trim_log
exit 0