#!/usr/bin/env bash
# install-stage3.sh — 阶段 3「检索与统计」的服务端安装 + 自检（幂等，可反复执行）
#
# 在 Workbench 里以 root 执行（本文件随仓库走，本地改完 push，服务器上重跑一次即可）：
#     bash /srv/blog/src/deploy/install-stage3.sh
#
# 铁律：只新增与替换，不删任何原始数据；nginx 配置替换前备份到 /root/stage3-backup/<ts>/；
#       venv 装坏即卸载复原（§0.2 K5）。输出全部是可回传的判据行（[OK]/[FAIL]/[NOTE] + 数字），
#       不打印任何凭据值。
set -uo pipefail

REPO=${REPO:-/srv/blog/src}
ETC=${ETC:-/etc/blog}
DATA=${DATA:-/srv/blog/data}
VENV=${VENV:-/opt/blogapi}
API=http://127.0.0.1:8000
BK=/root/stage3-backup/$(date +%Y%m%d-%H%M%S)
PASS=0; FAIL=0; NOTE=0
sec()  { printf '\n########## %s ##########\n' "$*"; }
ck()   { if [ "$2" = 0 ]; then PASS=$((PASS+1)); printf '[OK]   %s ｜ %s\n' "$1" "${3:-}"; else FAIL=$((FAIL+1)); printf '[FAIL] %s ｜ %s\n' "$1" "${3:-}"; fi; }
note() { NOTE=$((NOTE+1)); printf '[NOTE] %s ｜ %s\n' "$1" "${2:-}"; }
code() { curl -s -o /dev/null -w '%{http_code}' --noproxy '*' -m 8 "$@"; }
jget() { /usr/bin/python3 -c "import sys,json; d=json.load(sys.stdin); print($1)" 2>/dev/null; }

if [ "$(id -u)" != 0 ]; then echo '须以 root 运行' >&2; exit 5; fi

# 防「自己改写自己」：P1 的 git pull 会就地重写仓库里的本文件 -> 先落 /tmp 私有副本（与 stage2 同款）
case "$0" in
  "$REPO"/*)
    if cp -f "$0" /tmp/blog-stage3-install.sh && chmod 0700 /tmp/blog-stage3-install.sh; then
      exec bash /tmp/blog-stage3-install.sh "$@"
    fi
    echo '警告：本脚本没能复制到 /tmp，将继续就地执行' >&2
    ;;
esac

sec 'P0 前置实况（版本 / 资源 / 本脚本身份）'
printf '本脚本 sha256=%s\n' "$(sha256sum "$0" | cut -c1-16)"
printf '仓库 HEAD=%s\n' "$(sudo -u blog git -C "$REPO" rev-parse --short HEAD 2>/dev/null)"
printf 'python=%s ｜ 内存 %s\n' "$(python3 -V 2>&1)" "$(free -m | awk '/^Mem:/{print "used "$3"M / avail "$7"M"}')"
printf 'current -> %s\n' "$(readlink /srv/blog/current 2>/dev/null || echo 无)"
mkdir -p "$BK" && chmod 700 "$BK"
printf '备份目录=%s\n' "$BK"

sec 'P1 仓库文件与语法体检'
for f in scripts/blogapi.py scripts/reindex.py deploy/systemd/blog-api.service deploy/nginx/blog-locations.conf.tpl; do
  if [ -f "$REPO/$f" ]; then PASS=$((PASS+1)); printf '[OK]   存在 %s\n' "$f"; else ck "存在 $f" 1 '仓库里没有这个文件'; fi
done
CRLF=$(grep -rlI $'\r' "$REPO/scripts" "$REPO/deploy" 2>/dev/null | tr '\n' ' ')
if [ -z "$CRLF" ]; then ck '仓库换行符体检' 0 'scripts/ 与 deploy/ 全部 LF'; else ck '仓库换行符体检' 1 "检出 CR：$CRLF"; exit 8; fi
for f in scripts/blogapi.py scripts/reindex.py; do
  /usr/bin/python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' "$REPO/$f" 2> "$BK/pyc.log"
  ck "py 语法 $f" "$?" "$(tail -c 160 "$BK/pyc.log")"
done

sec 'P2 venv /opt/blogapi（§0.2 K5：新增 Python 组件一律 venv，绝不全局 pip）'
if [ ! -x "$VENV/bin/python" ]; then
  python3 -m venv "$VENV" > "$BK/venv.log" 2>&1
  ck '创建 venv' "$?" "$(tail -c 120 "$BK/venv.log" | tr '\n' ' ')"
else
  ck 'venv 已存在（复用）' 0 "$("$VENV/bin/python" -V 2>&1)"
fi
"$VENV/bin/pip" install --quiet --index-url https://mirrors.cloud.aliyuncs.com/pypi/simple/ \
  'fastapi>=0.110' 'uvicorn>=0.29' 'jieba==0.42.1' > "$BK/pip.log" 2>&1
ck 'pip 安装（内网源）' "$?" "$(tail -c 160 "$BK/pip.log" | tr '\n' ' ')"
if ! "$VENV/bin/python" -c 'import fastapi, uvicorn, jieba; print("fastapi", fastapi.__version__, "| uvicorn", uvicorn.__version__, "| jieba", jieba.__version__)' 2> "$BK/import.err"; then
  "$VENV/bin/pip" uninstall -y fastapi uvicorn jieba >/dev/null 2>&1
  ck 'venv 依赖可用性' 1 "装完仍不可用，已卸载复原：$(tail -c 200 "$BK/import.err" | tr '\n' ' ')；把上面 pip 日志尾回传定性"
  exit 7
fi
ck 'venv 依赖可用性' 0 "$("$VENV/bin/python" -c 'import fastapi,uvicorn,jieba; print("fastapi",fastapi.__version__,"| uvicorn",uvicorn.__version__,"| jieba",jieba.__version__)' 2>&1)"

sec 'P3 数据目录与 reindex token（只建不覆盖）'
mkdir -p "$DATA"; chown blog:blog "$DATA"; chmod 0755 "$DATA"
ck '数据目录' "$([ -d "$DATA" ] && [ -w "$DATA" ] && echo 0 || echo 1)" "$(ls -ld "$DATA" | awk '{print $1, $3":"$4, $9}')"
if [ ! -s "$ETC/api.env" ]; then
  (umask 077; printf 'REINDEX_TOKEN=%s\n' "$(openssl rand -hex 32)" > "$ETC/api.env")
fi
chown root:blog "$ETC/api.env"; chmod 0640 "$ETC/api.env"
TOKEN=$(sed -n 's/^REINDEX_TOKEN=//p' "$ETC/api.env" | tr -d '\r\n')
[ -n "$TOKEN" ]; ck 'api.env（值不打印）' "$?" "长度=${#TOKEN} 权限=$(stat -c '%a %U:%G' "$ETC/api.env")"
if [ -f "$ETC/deploy.env" ]; then
  cp -f "$ETC/deploy.env" "$BK/deploy.env.bak"
  if grep -q '^REINDEX_TOKEN=' "$ETC/deploy.env"; then
    sed -i "s|^REINDEX_TOKEN=.*|REINDEX_TOKEN=$TOKEN|" "$ETC/deploy.env"
  else
    printf 'REINDEX_TOKEN=%s\n' "$TOKEN" >> "$ETC/deploy.env"
  fi
  ck 'deploy.env 回填 REINDEX_TOKEN' "$([ "$(grep -c '^REINDEX_TOKEN=..*' "$ETC/deploy.env")" = 1 ] && echo 0 || echo 1)" "deploy.sh 第 7 步调用 reindex 时带上它"
fi

sec 'P4 systemd 装载与端口约束'
install -m 0644 -o root -g root "$REPO/deploy/systemd/blog-api.service" /etc/systemd/system/blog-api.service
systemd-analyze verify /etc/systemd/system/blog-api.service > "$BK/unit-verify.log" 2>&1
note 'systemd-analyze verify' "$(wc -l < "$BK/unit-verify.log") 行提示（为空即无告警）：$(head -c 200 "$BK/unit-verify.log" | tr '\n' ' ')"
systemctl daemon-reload; ck 'daemon-reload' "$?"
systemctl enable --now blog-api.service > "$BK/enable.log" 2>&1
ck 'enable --now blog-api' "$?" "$(tr '\n' ' ' < "$BK/enable.log" | head -c 120)"
OK=1
for i in $(seq 1 20); do
  [ "$(code "$API/healthz")" = 200 ] && { OK=0; break; }
  sleep 1
done
ck 'blog-api healthz 就绪' "$OK" "is-active=$(systemctl is-active blog-api 2>&1) 等待=${i}s"
ck '8000 只绑回环' "$(ss -ltn 2>/dev/null | grep -q '127.0.0.1:8000' && echo 0 || echo 1)" "$(ss -ltnp 2>/dev/null | grep ':8000' | head -1 | awk '{print $4}')"
ck '公网面未泄漏 9100/8000' "$(ss -ltn 2>/dev/null | grep -qE '(0\.0\.0\.0|\*):(:)?(9100|8000)' && echo 1 || echo 0)" "$(ss -ltn | awk 'NR>1{print $4}' | sort -u | tr '\n' ' ')"

sec 'P5 全量重建索引（解析 current 实际指向的 release）'
R=$(curl -fsS --noproxy '*' -m 120 -X POST -H "X-Reindex-Token: $TOKEN" -H 'Content-Type: application/json' \
  --data '{"full":true}' "$API/api/reindex")
ck 'POST /api/reindex {"full":true}' "$?" "${R:-（空响应）}"
N=$(printf '%s' "$R" | jget "d.get('indexed',0)")
[ "${N:-0}" -gt 0 ]; ck '索引篇数 > 0' "$?" "indexed=${N:-0}（本地同版实测 11）"
HZ=$(curl -fsS --noproxy '*' -m 5 "$API/healthz")
printf 'healthz：%s\n' "$HZ"

sec 'P6 渲染 Nginx locations（备份旧件 -> 渲染 -> nginx -t -> 失败即回滚）'
# shellcheck disable=SC1091
. "$ETC/site.env"
: "${SITE_DOMAIN:=tuanzi-wow.cn}" "${SITE_WWW:=www.tuanzi-wow.cn}" "${SITE_ROOT:=/srv/blog/current}" "${DEPLOY_ALLOW:=127.0.0.1 ::1}"
IPSN=""; [ -n "${IPSERVERNAME:-}" ] && IPSN=" ${IPSERVERNAME}"
HAVE_CERT=0; [ -s "/etc/letsencrypt/live/$SITE_DOMAIN/fullchain.pem" ] && HAVE_CERT=1
WWW301='# www 跳转未启用（证书未就绪时跳 https 会把人跳进死路）'
[ "$HAVE_CERT" = 1 ] && WWW301="if (\$host = $SITE_WWW) { return 301 https://$SITE_DOMAIN\$request_uri; }"
render() { sed -e "s|__DOMAIN__|$SITE_DOMAIN|g" -e "s|__WWW__|$SITE_WWW|g" -e "s|__ROOT__|$SITE_ROOT|g" -e "s|__IPSN__|$IPSN|g" -e "s|__WWW301__|$WWW301|g" "$1"; }
# /_deploy 与 /api/reindex 共用同一份 allow 白名单（源 = site.env 的 DEPLOY_ALLOW，幂等重建）
[ -f /etc/nginx/snippets/blog-deploy-allow.conf ] && cp -f /etc/nginx/snippets/blog-deploy-allow.conf "$BK/blog-deploy-allow.conf.bak"
: > /etc/nginx/snippets/blog-deploy-allow.conf
for ip in $DEPLOY_ALLOW; do printf 'allow %s;\n' "$ip" >> /etc/nginx/snippets/blog-deploy-allow.conf; done
printf 'deny all;\n' >> /etc/nginx/snippets/blog-deploy-allow.conf
chmod 0644 /etc/nginx/snippets/blog-deploy-allow.conf
cp -f /etc/nginx/snippets/blog-locations.conf "$BK/blog-locations.conf.bak" 2>/dev/null
if render "$REPO/deploy/nginx/blog-locations.conf.tpl" > /etc/nginx/snippets/blog-locations.conf.tmp; then
  mv -Tf /etc/nginx/snippets/blog-locations.conf.tmp /etc/nginx/snippets/blog-locations.conf
  ck '渲染 locations（启用 /api/）' 0 "api 块数=$(grep -c 'location .*api' /etc/nginx/snippets/blog-locations.conf)"
else
  ck '渲染 locations' 1 'sed 失败'; exit 6
fi
nginx -t > "$BK/nginx-t.log" 2>&1
if [ "$?" != 0 ]; then
  ck 'nginx -t' 1 "$(tail -c 400 "$BK/nginx-t.log" | tr '\r' ' ' | tr '\n' ' ')"
  [ -f "$BK/blog-locations.conf.bak" ] && cp -f "$BK/blog-locations.conf.bak" /etc/nginx/snippets/blog-locations.conf
  [ -f "$BK/blog-deploy-allow.conf.bak" ] && cp -f "$BK/blog-deploy-allow.conf.bak" /etc/nginx/snippets/blog-deploy-allow.conf
  systemctl reload nginx 2>/dev/null
  note '回滚' 'locations 已还原安装前内容，线上仍按旧规则服务；把上面 nginx -t 报错原样回传'
  exit 6
fi
systemctl reload nginx; ck 'nginx -t + reload' "$?" "reload rc=$?"
C=$(code -H "Host: $SITE_DOMAIN" http://127.0.0.1/)
ck '静态页仍 200（locations 改动未伤及页面）' "$([ "$C" = 200 ] && echo 0 || echo 1)" "code=$C"

sec 'P7 端到端自检（回环 + Host 头；域名公网维度仍等 0.11 备案）'
H="Host: $SITE_DOMAIN"
for w in 标准库 浮点 异常; do
  R=$(curl -fsS --noproxy '*' -m 5 -G -H "$H" --data-urlencode "q=$w" http://127.0.0.1/api/search)
  TOTAL=$(printf '%s' "$R" | jget "d.get('total',0)")
  URL1=$(printf '%s' "$R" | jget "(d['hits'][0]['url'] if d.get('hits') else '')")
  ANC=$(printf '%s' "$R" | jget "(d['hits'][0].get('anchor','') if d.get('hits') else '')")
  [ "${TOTAL:-0}" -ge 1 ]; ck "搜索「$w」命中" "$?" "total=$TOTAL 首命中=$URL1#$ANC"
done
R=$(curl -fsS --noproxy '*' -m 5 -G -H "$H" --data-urlencode 'q=浮点' http://127.0.0.1/api/search)
M=$(printf '%s' "$R" | jget "'<mark>' in (d['hits'][0].get('snippet','') if d.get('hits') else '')")
[ "$M" = "True" ]; ck '摘要含 <mark> 高亮' "$?"
curl -fsS --noproxy '*' -m 5 -H "$H" -X POST --data '{"u":"/python/stage3-selfcheck-a/","r":"https://www.bing.com/search?q=stage3","v":"stage3selfcheck1"}' http://127.0.0.1/api/visit -o /dev/null
curl -fsS --noproxy '*' -m 5 -H "$H" -X POST --data '{"u":"/python/stage3-selfcheck-b/","r":"https://www.google.com/","v":"stage3selfcheck2"}' http://127.0.0.1/api/visit -o /dev/null
S=$(curl -fsS --noproxy '*' -m 5 -H "$H" "http://127.0.0.1/api/stats?days=7")
PV=$(printf '%s' "$S" | jget "d.get('pv',0)")
UV=$(printf '%s' "$S" | jget "d.get('uv',0)")
TOP=$(printf '%s' "$S" | jget "any(t['url']=='/python/stage3-selfcheck-a/' for t in d.get('top',[]))")
REF=$(printf '%s' "$S" | jget "any(r['host'] in ('www.bing.com','bing.com') for r in d.get('refs',[]))")
[ "${PV:-0}" -ge 2 ] && [ "${UV:-0}" -ge 2 ] && [ "$TOP" = "True" ] && [ "$REF" = "True" ]
ck 'visit -> stats 一致' "$?" "pv=$PV uv=$UV 热门页含自检路径=$TOP 来源站含 bing=$REF"
C1=$(code -X POST "$API/api/reindex")
C2=$(code -X POST -H 'X-Reindex-Token: wrong' "$API/api/reindex")
C3=$(code -X POST -H "$H" http://127.0.0.1/api/reindex)
[ "$C1" = 401 ] && [ "$C2" = 401 ] && [ "$C3" = 401 ]
ck 'reindex 无/错 token 一律 401' "$?" "直连无=$C1 直连错=$C2 经nginx无=$C3（nginx 白名单放行回环，应用层拒绝）"
for i in 1 2 3; do curl -s --noproxy '*' -o /dev/null -G --data-urlencode 'q=python' "$API/api/search"; done
for i in $(seq 1 30); do
  curl -s --noproxy '*' -o /dev/null -w '%{time_total}\n' -m 5 -G -H "$H" --data-urlencode 'q=标准库' http://127.0.0.1/api/search
  sleep 0.12
done | sort -n > "$BK/lat.txt"
P95=$(awk '{a[NR]=$1} END{i=int(NR*0.95); if(i<1)i=1; printf "%.1f", a[i]*1000}' "$BK/lat.txt")
awk -v p="$P95" 'BEGIN{exit !(p<20)}'; ck '搜索 p95 < 20 ms（经 nginx，30 次取第 28 名）' "$?" "p95=${P95}ms"

sec 'P8 收尾实况'
RSS=$(ps -o rss= -p "$(systemctl show -p MainPID --value blog-api)" 2>/dev/null | awk '{print int($1/1024)}')
note "blog-api RSS=${RSS:-?}MiB" "稳态判据 ≤200MiB（jieba 词典约占 60MiB，刚启动属正常）"
printf '内存：'; free -m | awk '/^Mem:/{print "used "$3"M avail "$7"M"} /^Swap:/{print "｜ swap used "$3"M"}'
printf '监听：%s\n' "$(ss -ltn 2>/dev/null | awk 'NR>1{print $4}' | sort -u | tr '\n' ' ')"
printf 'journalctl 尾部：\n'
journalctl -u blog-api.service -n 5 --no-pager -o short-iso 2>/dev/null | sed 's/^/  /'
printf '\n下一步（自动）：\n'
printf '  1) 前端搜索页与页脚埋点已随本次仓库更新由 blog-poll.timer 自动发布，/search/ 与页脚搜索框即生效\n'
printf '  2) 之后每次 push，deploy.sh 第 7 步会带 token 增量重建索引（新文章 5 s 内可搜）\n'
printf '  3) 域名公网维度的搜索/埋点验证仍等 0.11 备案生效（§0.2 K3）\n'
printf '\nSTAGE3-DONE pass=%s fail=%s note=%s\n' "$PASS" "$FAIL" "$NOTE"
exit 0
