#!/usr/bin/env bash
# install-stage2.sh — 阶段 2「部署链路」的服务端安装 + 自检（幂等，可反复执行）
#
# 在 Workbench 里以 root 执行（本文件随仓库走，本地改完 push，服务器上重跑一次即可）：
#     bash /srv/blog/src/deploy/install-stage2.sh
# 开关：
#     --no-deploy    只安装不发布（先看状态）
#     --issue-cert   只做证书签发/续期检查（需先在 /etc/blog/dns-aliyun.ini 填好 RAM AK）
#     --show-secret  打印 webhook 密钥明文（要把密钥粘进 GitHub Webhook 设置时用；默认绝不打印）
#
# 铁律：只新增与替换，不删任何原始数据。被替换的 nginx 配置先备份到 /root/stage2-backup/<ts>/。
# 输出全部是可回传给 agent 的判据行（[OK]/[FAIL]/[NOTE] + 数字），不打印任何凭据值。
set -uo pipefail

REPO=${REPO:-/srv/blog/src}
BIN=${BIN:-/srv/blog/bin}
ETC=${ETC:-/etc/blog}
BK=/root/stage2-backup/$(date +%Y%m%d-%H%M%S)
VHOST=tuanzi-wow
MODE=install
DO_DEPLOY=1
for a in "$@"; do
  case "$a" in
    --no-deploy) DO_DEPLOY=0 ;;
    --issue-cert) MODE=cert ;;
    --show-secret) MODE=show ;;
    *) printf '未知参数：%s\n' "$a" >&2; exit 4 ;;
  esac
done
PASS=0; FAIL=0; NOTE=0
sec()  { printf '\n########## %s ##########\n' "$*"; }
ck()   { if [ "$2" = 0 ]; then PASS=$((PASS+1)); printf '[OK]   %s ｜ %s\n' "$1" "${3:-}"; else FAIL=$((FAIL+1)); printf '[FAIL] %s ｜ %s\n' "$1" "${3:-}"; fi; }
note() { NOTE=$((NOTE+1)); printf '[NOTE] %s ｜ %s\n' "$1" "${2:-}"; }

if [ "$(id -u)" != 0 ]; then echo '须以 root 运行' >&2; exit 5; fi

if [ "$MODE" = show ]; then
  if [ -r "$ETC/webhook-secret" ]; then
    printf '把下面这一整行粘进 GitHub → Settings → Webhooks → Secret：\n'
    cat "$ETC/webhook-secret"; printf '\n'
  else
    printf '还没有 %s/webhook-secret，先跑一次安装\n' "$ETC" >&2; exit 2
  fi
  exit 0
fi

# 防「自己改写自己」：bash 按字节偏移边读边执行，而 P1 的 git pull 会就地重写仓库里的本文件 ->
# /tmp 落一份私有副本再 exec 过去，之后脚本内容与仓库变更解耦（副本 = bootstrap 那次 pull 到的版本）
case "$0" in
  "$REPO"/*)
    if cp -f "$0" /tmp/blog-stage2-install.sh && chmod 0700 /tmp/blog-stage2-install.sh; then
      exec bash /tmp/blog-stage2-install.sh "$@"
    fi
    echo '警告：本脚本没能复制到 /tmp，将继续就地执行；P1 若改写本文件，行为不可预测' >&2
    ;;
esac

sec 'P0 前置实况（版本 / 资源 / 本脚本身份）'
printf '本脚本 sha256=%s\n' "$(sha256sum "$0" | cut -c1-16)"
printf '仓库 HEAD=%s 工作区脏行数=%s\n' "$(sudo -u blog git -C "$REPO" rev-parse --short HEAD 2>/dev/null)" "$(sudo -u blog git -C "$REPO" status --porcelain 2>/dev/null | wc -l)"
printf 'hugo=%s nginx=%s python=%s certbot=%s\n' "$(hugo version 2>/dev/null | head -1 | cut -d, -f1)" "$(nginx -v 2>&1 | cut -d/ -f2)" "$(python3 -V 2>&1)" "$(/usr/local/bin/certbot --version 2>&1 | head -1)"
printf '内存 %s ｜ 磁盘 %s ｜ 负载 %s\n' "$(free -m | awk '/^Mem:/{print "used "$3"M / avail "$7"M"}')" "$(df -h / | awk 'NR==2{print $3"/"$2" ("$5")"}')" "$(cut -d' ' -f1-3 /proc/loadavg)"
mkdir -p "$BK" && chmod 700 "$BK"
printf '备份目录=%s\n' "$BK"

sec 'P1 同步仓库（blog 身份 ff-only；GitHub 的 HTTP/2 在这台机上会报 curl 16，故强制 1.1 + 退避重试）'
rc=1; tries=0
for wait_s in 0 2 5 10; do
  tries=$((tries + 1))
  [ "$wait_s" -gt 0 ] && sleep "$wait_s"
  if timeout -k 5 60 sudo -u blog git -C "$REPO" -c http.version=HTTP/1.1 pull --ff-only origin main > "$BK/pull.log" 2>&1; then rc=0; break; fi
done
HEAD_NOW=$(sudo -u blog git -C "$REPO" rev-parse --short HEAD 2>/dev/null)
ck 'git pull --ff-only' "$rc" "第 ${tries} 次尝试成功｜HEAD=$HEAD_NOW｜日志尾=$(tail -c 160 "$BK/pull.log" | tr '\n' ' ')"
if [ "$rc" != 0 ]; then echo '仓库没更新：后面装的就是旧文件，把上面日志尾回传定性' >&2; exit 3; fi
# 仓库里只要有一个 CRLF 文件被当成脚本/模板用，就会产生带 \r 的 nginx 配置与跑不动的 bash —— 装之前先整体体检
CRLF_HITS=$(grep -rlI $'\r' "$REPO/deploy" "$REPO/scripts" 2>/dev/null | tr '\n' ' ')
if [ -n "$CRLF_HITS" ]; then echo "检出 CR 的文件：$CRLF_HITS" >&2; exit 8; fi
[ -z "$CRLF_HITS" ]; ck '仓库换行符体检' 0 "deploy/ 与 scripts/ 全部 LF"
sec 'P2 安装 /srv/blog/bin（root 持有 0755，blog 不可改）'
mkdir -p "$BIN"
for f in scripts/deploy.sh scripts/deploy-hook.py; do
  src="$REPO/$f"
  if [ ! -f "$src" ]; then ck "存在 $f" 1 '仓库里没有这个文件'; continue; fi
  if grep -q $'\r' "$src"; then ck "换行符 $f" 1 '检出为 CRLF，会被 bash/python 咬到（查 .gitattributes）'; continue; fi
  cp -f "$src" "$BIN/$(basename "$f")"
  chmod 0755 "$BIN/$(basename "$f")"; chown root:root "$BIN/$(basename "$f")"
done
bash -n "$BIN/deploy.sh" 2> "$BK/bashn.log"; ck 'deploy.sh 语法' "$?" "$(cat "$BK/bashn.log")"
python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' "$BIN/deploy-hook.py" 2> "$BK/pyc.log"; ck 'deploy-hook.py 语法' "$?" "$(tail -c 200 "$BK/pyc.log")"
rm -rf -- "$BIN/__pycache__"   # 上一版 py_compile 留下的残骸，别混进 bin 清单
ls -l "$BIN" | awk 'NR>1{print "  " $1, $3":"$4, $9}'

sec 'P3 /etc/blog 与凭据位（只建不覆盖，权限收紧）'
mkdir -p "$ETC"; chown root:root "$ETC"; chmod 0750 "$ETC"
if [ ! -s "$ETC/webhook-secret" ]; then
  (umask 077; openssl rand -hex 32 > "$ETC/webhook-secret")
  printf '[OK]   已生成 webhook-secret ｜ 长度=%s 指纹=%s（明文只在 --show-secret 时打印）\n' "$(tr -d '\n' < "$ETC/webhook-secret" | wc -c)" "$(sha256sum "$ETC/webhook-secret" | cut -c1-8)"
  PASS=$((PASS+1))
else
  ck 'webhook-secret 已存在（保留不覆盖）' 0 "长度=$(tr -d '\n' < "$ETC/webhook-secret" | wc -c) 指纹=$(sha256sum "$ETC/webhook-secret" | cut -c1-8)"
fi
install -m 0600 -o root -g root "$REPO/deploy/defaults/deploy.env.example" "$ETC/deploy.env.tmp" && { [ -s "$ETC/deploy.env" ] || mv -f "$ETC/deploy.env.tmp" "$ETC/deploy.env"; rm -f "$ETC/deploy.env.tmp"; }
[ -s "$ETC/deploy.env" ]; ck 'deploy.env' "$?" "$(ls -l "$ETC/deploy.env" 2>/dev/null | awk '{print $1}')"
if [ ! -s "$ETC/site.env" ]; then
  PUBIP=$(curl -s -m 3 http://100.100.100.200/latest/meta-data/eipv4 2>/dev/null)
  case "$PUBIP" in *.*.*.*) : ;; *) PUBIP=$(hostname -I 2>/dev/null | awk '{print $1}') ;; esac
  sed -e "s|^ECS_IP=.*|ECS_IP=$PUBIP|" "$REPO/deploy/defaults/site.env.example" > "$ETC/site.env"
  chmod 0600 "$ETC/site.env"
fi
ck 'site.env' "$([ -s "$ETC/site.env" ] && echo 0 || echo 1)" "$(awk -F= '/^SITE_DOMAIN|^ECS_IP|^IPSERVERNAME|^DEPLOY_ALLOW/{printf "%s ", $0}' "$ETC/site.env")"
ls -ld "$ETC" "$ETC"/* 2>/dev/null | awk '{print "  " $1, $3":"$4, $9}'

sec 'P4 渲染 Nginx 配置（备份旧件 -> 渲染 -> nginx -t -> 失败即回滚）'
# shellcheck disable=SC1091
. "$ETC/site.env"
: "${SITE_DOMAIN:=tuanzi-wow.cn}" "${SITE_WWW:=www.tuanzi-wow.cn}" "${SITE_ROOT:=/srv/blog/current}" "${DEPLOY_ALLOW:=127.0.0.1 ::1}"
# 备案期开关：IPSERVERNAME 有值时 IP 直访也落到博客（置空后回到 default_server 的 404）
# site.env 是被 source 的：IPSERVERNAME=$ECS_IP 在 source 时就已展开；置空即让 IP 直访回到 default_server 的 404
IPSN=""; [ -n "${IPSERVERNAME:-}" ] && IPSN=" ${IPSERVERNAME}"
CERT_DIR=/etc/letsencrypt/live/$SITE_DOMAIN
HAVE_CERT=0; [ -s "$CERT_DIR/fullchain.pem" ] && HAVE_CERT=1
WWW301='# www 跳转未启用（证书未就绪时跳 https 会把人跳进死路）'
[ "$HAVE_CERT" = 1 ] && WWW301="if (\$host = $SITE_WWW) { return 301 https://$SITE_DOMAIN\$request_uri; }"
TPL=$REPO/deploy/nginx
render() { sed -e "s|__DOMAIN__|$SITE_DOMAIN|g" -e "s|__WWW__|$SITE_WWW|g" -e "s|__ROOT__|$SITE_ROOT|g" -e "s|__IPSN__|$IPSN|g" -e "s|__WWW301__|$WWW301|g" "$1"; }
RENDERED=
for pair in "$TPL/blog-locations.conf.tpl:/etc/nginx/snippets/blog-locations.conf" "$TPL/tuanzi-wow.conf.tpl:/etc/nginx/sites-available/$VHOST.conf" "$TPL/tuanzi-wow.ssl.conf.tpl:/etc/nginx/sites-available/$VHOST.ssl.conf"; do
  t=${pair%%:*}; d=${pair#*:}
  mkdir -p "$(dirname "$d")"
  if [ -f "$d" ]; then cp -f "$d" "$BK/$(basename "$d").bak"; fi
  render "$t" > "$d.tmp" && mv -Tf "$d.tmp" "$d" && RENDERED="$RENDERED $d"
done
[ -f /etc/nginx/snippets/blog-deploy-allow.conf ] && cp -f /etc/nginx/snippets/blog-deploy-allow.conf "$BK/blog-deploy-allow.conf.bak"
: > /etc/nginx/snippets/blog-deploy-allow.conf
for ip in $DEPLOY_ALLOW; do printf 'allow %s;\n' "$ip" >> /etc/nginx/snippets/blog-deploy-allow.conf; done
printf 'deny all;\n' >> /etc/nginx/snippets/blog-deploy-allow.conf
chmod 0644 /etc/nginx/snippets/blog-deploy-allow.conf
ln -sfn /etc/nginx/sites-available/$VHOST.conf /etc/nginx/sites-enabled/$VHOST.conf
if [ "$HAVE_CERT" = 1 ]; then ln -sfn /etc/nginx/sites-available/$VHOST.ssl.conf /etc/nginx/sites-enabled/$VHOST.ssl.conf; note '证书已就绪，HTTPS 站块已启用'; else rm -f /etc/nginx/sites-enabled/$VHOST.ssl.conf; note '证书未签发，本轮只启用 80（DNS-01 见 --issue-cert）'; fi
printf 'sites-enabled: %s\n' "$(ls -1 /etc/nginx/sites-enabled/ 2>/dev/null | tr '\n' ' ')"
sec 'P5 压缩与模块探测（apt 版 nginx 无 brotli 就只写 gzip；逐指令判重，主配置已有的绝不覆写）'
BROTLI=0; nginx -V 2>&1 | grep -qE 'brotli' && BROTLI=1
BMSG=无-退回gzip; [ "$BROTLI" = 1 ] && BMSG=有
note 'brotli 模块' "$BMSG"
TYPES='text/css text/plain text/xml application/javascript application/json application/manifest+json application/xml image/svg+xml'
# 探针数据 = nginx -T 的全部生效配置，但要排除我们自己这份 drop-in：
# 否则第二次跑会把「上一轮自己写的行」当成主配置已有 -> 静默退化成只剩 gzip on（D24）
# nginx -T 本身带配置校验，它失败就说明当前磁盘配置是坏的，探针不可信 -> 宁可不写
WROTE_COMP=0
COMP_CONF=/etc/nginx/conf.d/zz-blog-compression.conf
if nginx -T > "$BK/nginx-T.txt" 2> "$BK/nginx-T.err"; then
  awk '/^# configuration file /{keep=(index($0,"zz-blog-compression.conf")==0)} keep' "$BK/nginx-T.txt" > "$BK/probe.txt"
  has_dir() { grep -qE "^[[:space:]]*$1[[:space:]]" "$BK/probe.txt"; }
  add_dir() { if has_dir "$1"; then printf '# %-16s 主配置已有，跳过\n' "$1"; else printf '%s %s;\n' "$1" "$2"; fi; }
  {
    printf '# 生成物（勿手改）：install-stage2.sh 逐指令判重，只补主配置里缺的那几条。\n'
    printf '# 这些指令在 http 上下文只能出现一次，写重了 nginx -t 直接 emerg: "gzip" directive is duplicate。\n'
    add_dir gzip on
    add_dir gzip_vary on
    add_dir gzip_comp_level 5
    add_dir gzip_min_length 1024
    add_dir gzip_proxied any
    add_dir gzip_types "$TYPES"
    if [ "$BROTLI" = 1 ]; then
      add_dir brotli on
      add_dir brotli_comp_level 5
      add_dir brotli_min_length 1024
      add_dir brotli_types "$TYPES"
    fi
  } > "$COMP_CONF"
  chmod 0644 "$COMP_CONF"; WROTE_COMP=1
  note '压缩 drop-in' "已写 $COMP_CONF ｜ 探针见 $(wc -l < "$BK/probe.txt") 行 ｜ 跳过 $(grep -c '主配置已有' "$COMP_CONF") 条 ｜ 实补 $(grep -cE '^[a-z]' "$COMP_CONF") 条"
else
  note '压缩 drop-in' "nginx -T 失败 -> 本轮不写，保留原压缩配置；报错随 P6 定性：$(tail -c 200 "$BK/nginx-T.err" | tr -d '\n')"
fi

sec 'P6 配置校验：nginx -t 不过就整批回滚到安装前'
nginx -t > "$BK/nginx-t.log" 2>&1; rc=$?
if [ "$rc" != 0 ]; then
  ck 'nginx -t' 1 "$(tail -c 500 "$BK/nginx-t.log" | tr -d '\r' | tr '\n' ' ')"
  for d in $RENDERED; do b="$BK/$(basename "$d").bak"; if [ -f "$b" ]; then cp -f "$b" "$d"; else rm -f "$d"; fi; done
  [ -f "$BK/blog-deploy-allow.conf.bak" ] && cp -f "$BK/blog-deploy-allow.conf.bak" /etc/nginx/snippets/blog-deploy-allow.conf || rm -f /etc/nginx/snippets/blog-deploy-allow.conf
  [ "$WROTE_COMP" = 1 ] && rm -f /etc/nginx/conf.d/zz-blog-compression.conf
  rm -f "/etc/nginx/sites-enabled/$VHOST.conf" "/etc/nginx/sites-enabled/$VHOST.ssl.conf"
  systemctl reload nginx 2>/dev/null
  note '回滚' '已还原安装前配置，线上仍按旧规则服务；把上面 nginx -t 的报错原样回传'
  exit 6
fi
systemctl reload nginx; rc=$?
ck 'nginx -t + reload' "$rc" "reload rc=$rc；$(tail -c 100 "$BK/nginx-t.log" | tr -d '\n' | tr -s ' ')"

sec 'P7 systemd 单元装载'
for u in blog-deploy-hook.service blog-poll.service blog-poll.timer blog-certbot-renew.service blog-certbot-renew.timer; do
  if [ -f "$REPO/deploy/systemd/$u" ]; then install -m 0644 -o root -g root "$REPO/deploy/systemd/$u" "/etc/systemd/system/$u"; fi
done
systemd-analyze verify /etc/systemd/system/blog-*.service /etc/systemd/system/blog-*.timer > "$BK/unit-verify.log" 2>&1
note 'systemd-analyze verify' "$(wc -l < "$BK/unit-verify.log") 行提示（为空即无告警）：$(head -c 300 "$BK/unit-verify.log" | tr '\n' ' ')"
systemctl daemon-reload; ck 'daemon-reload' "$?" "unit 文件已重读"
# 只 enable 两个「常驻/定时」单元：blog-poll.service 是 oneshot 且无 [Install]，由 timer 拉起，enable 它会报错
# 必须 --now：enable 只建符号链接、不启动。实跑就是栽在这：timer 没激活 -> 分钟级更新的主链路根本没跑（D26）
systemctl enable --now blog-deploy-hook.service blog-poll.timer > "$BK/enable.log" 2>&1
ck 'enable --now hook + poll timer' "$?" "$(tr '\n' ' ' < "$BK/enable.log" | head -c 160)"
ck 'blog-poll.timer 已激活' "$([ "$(systemctl is-active blog-poll.timer 2>&1)" = active ] && echo 0 || echo 1)" "is-active=$(systemctl is-active blog-poll.timer 2>&1) ｜ 下次=$(systemctl list-timers --no-legend blog-poll.timer 2>/dev/null | awk '{print $2, $3, $4}')（为空=只 enable 没 start）"
systemctl restart blog-deploy-hook.service; sleep 1
ck '9100 只绑回环' "$(ss -ltn 2>/dev/null | grep -q '127.0.0.1:9100' && echo 0 || echo 1)" "$(ss -ltnp 2>/dev/null | grep ':9100' | head -1)"
ck '公网面未泄漏 9100/8000' "$(ss -ltn 2>/dev/null | grep -qE '0\.0\.0\.0:(9100|8000)' && echo 1 || echo 0)" "$(ss -ltn | awk 'NR>1{print $4}' | sort -u | tr '\n' ' ')"

sec 'P8 证书链路（DNS-01；插件装不上就退回人工 TXT，不硬来）'
if ! /usr/local/bin/certbot plugins 2>/dev/null | grep -q 'dns-aliyun'; then
  before=$(/usr/local/bin/certbot --version 2>&1)
  /opt/certbot/bin/pip install --quiet --index-url https://mirrors.cloud.aliyuncs.com/pypi/simple/ certbot-dns-aliyun > "$BK/pip-dns.log" 2>&1; prc=$?
  note 'pip certbot-dns-aliyun' "rc=$prc 日志尾=$(tail -c 160 "$BK/pip-dns.log" | tr '\n' ' ')"
  if ! /usr/local/bin/certbot plugins 2>/dev/null | grep -q 'dns-aliyun' || ! /usr/local/bin/certbot --version >/dev/null 2>&1; then
    /opt/certbot/bin/pip uninstall -y certbot-dns-aliyun >/dev/null 2>&1
    ck 'dns-aliyun 插件可用性' 1 "装完仍不可用，已卸载复原（certbot 版本回验=$(/usr/local/bin/certbot --version 2>&1)）；证书改走人工 TXT 或换插件"
  else
    ck 'dns-aliyun 插件可用性' 0 "certbot=$before -> $(/usr/local/bin/certbot plugins 2>/dev/null | grep -A1 dns-aliyun | head -1)"
  fi
else
  ck 'dns-aliyun 插件可用性' 0 '已装'
fi
if [ ! -s "$ETC/dns-aliyun.ini" ]; then
  install -m 0600 -o root -g root "$REPO/deploy/certbot/dns-aliyun.ini.example" "$ETC/dns-aliyun.ini"
  note 'dns-aliyun.ini' "已放模板（含 REPLACE_ME），AK/SK 由你在服务器上填：$ETC/dns-aliyun.ini（脚本不回显其内容）"
fi
grep -q 'REPLACE_ME' "$ETC/dns-aliyun.ini" 2>/dev/null; NEED_AK=$?
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
printf '#!/bin/sh\n# 续期成功后重载 nginx，让它换上新证书链（DNS-01 不依赖 80，所以只 reload）\nnginx -t && systemctl reload nginx\n' > /etc/letsencrypt/renewal-hooks/deploy/00-blog-reload-nginx.sh
chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/00-blog-reload-nginx.sh
NATIVE=$(systemctl list-timers --all --no-legend 2>/dev/null | grep -ciE 'certbot|letsencrypt')
if [ "$NATIVE" -gt 0 ]; then
  note '续期 timer' "系统里已有 certbot/letsencrypt timer $NATIVE 个，我们的 blog-certbot-renew.timer 不启用（避免双跑）"
  systemctl disable --now blog-certbot-renew.timer > /dev/null 2>&1
else
  systemctl enable --now blog-certbot-renew.timer > "$BK/timer.log" 2>&1
  ck 'blog-certbot-renew.timer' "$?" "$(systemctl is-enabled blog-certbot-renew.timer 2>&1)"
fi
if [ "$MODE" = cert ]; then
  if [ "$NEED_AK" = 0 ]; then echo "$ETC/dns-aliyun.ini 里还有 REPLACE_ME，填好 RAM AK/SK 再重跑 --issue-cert" >&2; exit 7; fi
  sec 'P8b 签发/续期（--keep-until-expiring：已有有效证书即直接跳过）'
  MAILARGS=(--register-unsafely-without-email)
  # shellcheck disable=SC1091
  . "$ETC/site.env"
  [ -n "${CERTBOT_EMAIL:-}" ] && MAILARGS=(-m "$CERTBOT_EMAIL")
  [ "${MAILARGS[0]}" != "-m" ] && note '无邮箱注册' 'LE 不会发到期满提醒邮件；想收就在 /etc/blog/site.env 填 CERTBOT_EMAIL=xxx 后重跑 --issue-cert（阶段 4 另有本地告警兜底）'
  # certbot 2.x 起必须显式 --agree-tos：只给 --non-interactive 不会替你同意，而是直接退出（实跑栽过一次）
  /usr/local/bin/certbot certonly --non-interactive --agree-tos --no-eff-email --keep-until-expiring "${MAILARGS[@]}" \
    --authenticator dns-aliyun --dns-aliyun-credentials "$ETC/dns-aliyun.ini" \
    -d "$SITE_DOMAIN" -d "$SITE_WWW" > "$BK/certbot.log" 2>&1; crc=$?
  ck 'certbot certonly' "$crc" "$(tail -c 400 "$BK/certbot.log" | tr '\n' ' ')"
  if [ "$crc" = 0 ]; then
    /usr/local/bin/certbot certificates 2>/dev/null | awk '/Certificate Name|Domains|Expiry Date/{print "  "$0}'
    note '续跑安装' '证书已就绪，重跑一次 install（不带参数）以启用 443 站块与 www 跳转'
  else
    note '证书未签出' '把上面 certbot 输出尾部回传定性；期间 80 与 timer 更新链路不受影响'
  fi
  exit "$crc"
fi

sec 'P9 小结（进入发布与自检前）'
printf 'pass=%s fail=%s note=%s ｜ 备份=%s\n' "$PASS" "$FAIL" "$NOTE" "$BK"

if [ "$DO_DEPLOY" = 1 ]; then
  sec 'P10 首次发布（deploy.sh --force：构建 -> 自检 -> 原子切软链 -> reload）'
  "$BIN/deploy.sh" --force; drc=$?
  ck 'deploy.sh --force' "$([ "$drc" = 0 ] && echo 0 || echo 1)" "rc=$drc"
  printf 'deploy.log 末尾：\n'; tail -n 6 /srv/blog/logs/deploy.log 2>/dev/null | sed 's/^/  /'
  printf '构建统计：\n'; grep -E 'Total|Pages|WARN|ERROR' /srv/blog/logs/last-build.log 2>/dev/null | tail -n 8 | sed 's/^/  /'
fi

sec 'P11 端到端自检（回环 + Host 头：备案审核期同样能验，只有域名公网维度被云平台拦）'
code() { curl -s -o /dev/null -w '%{http_code}' --noproxy '*' -m 8 "$@"; }   # 失败时 curl 自己就输出 000，别再 || echo 一次
H="Host: $SITE_DOMAIN"
# 裸 127.0.0.1 当 Host 只会命中 default_server 的 404，验不出 IP 直访；要用 site.env 里的公网 IP 作 Host（D25）
IPSN_IP="${IPSERVERNAME:-${ECS_IP:-}}"
IPSN_EXPECT=200; [ -z "$IPSN_IP" ] && IPSN_EXPECT=404   # 备案生效后把 IPSERVERNAME 置空 -> IP 直访回到 404 占位
C1=$(code -H "$H" http://127.0.0.1/)
ck 'GET / 首页 200' "$([ "$C1" = 200 ] && echo 0 || echo 1)" "code=$C1"
C2=$(code -H "$H" http://127.0.0.1/python/)
ck 'GET /python/ 分区页 200' "$([ "$C2" = 200 ] && echo 0 || echo 1)" "code=$C2"
C3=$(code -H "$H" http://127.0.0.1/no-such-page-404)
ck 'GET 不存在的页面 404（不是 500，见 §0.2 K8）' "$([ "$C3" = 404 ] && echo 0 || echo 1)" "code=$C3"
C4=$(code http://127.0.0.1/)
C5=$(code -H "Host: $IPSN_IP" http://127.0.0.1/)
ck 'IP 直访命中博客' "$([ "$C5" = "$IPSN_EXPECT" ] && echo 0 || echo 1)" "Host=<公网IP>=$C5 期望=$IPSN_EXPECT ｜ 裸 Host 127.0.0.1=$C4（必为 404，落到 00-default 占位）"
printf '响应头（页面）：\n'; curl -sI -H "$H" http://127.0.0.1/ --noproxy '*' | grep -iE '^(HTTP/|cache-control|content-type|server|x-content|strict)' | sed 's/^/  /'
CSS=$(find /srv/blog/current/ -type f -name '*.css' 2>/dev/null | head -1)   # 末尾斜杠：find 才会跟着 current 这个软链
printf '响应头（资源 %s）：\n' "$(basename "${CSS:-none}")"; curl -sI -H "$H" "http://127.0.0.1${CSS#/srv/blog/current}" --noproxy '*' --compressed | grep -iE '^(HTTP/|cache-control|content-type|content-encoding)' | sed 's/^/  /'
note 'gzip 生效判据' "上面 content-encoding 若为空，多半是文件小于 gzip_min_length=1024 或 curl 未带 Accept-Encoding，别当故障"
printf 'webhook 接收器 healthz：%s\n' "$(curl -s --noproxy '*' -m 5 http://127.0.0.1:9100/healthz)"
printf '{"ref":"refs/heads/main","after":"0000000000000000000000000000000000000000","deleted":false}' > "$BK/hook-body.json"
SIG=$(/usr/bin/python3 "$BIN/deploy-hook.py" --secret-file "$ETC/webhook-secret" --sign-body "$BK/hook-body.json" 2>/dev/null)
W1=$(curl -s -o "$BK/hook1.txt" -w '%{http_code}' --noproxy '*' -m 10 -X POST -H "Host: $SITE_DOMAIN" -H 'X-GitHub-Event: ping' -H "X-Hub-Signature-256: $SIG" --data-binary "@$BK/hook-body.json" http://127.0.0.1/_deploy)
ck '经 nginx /_deploy 的签名校验链路可达' "$([ "$W1" = 200 ] || [ "$W1" = 202 ] && echo 0 || echo 1)" "code=$W1 响应=$(head -c 60 "$BK/hook1.txt")（ping 事件被 ignored 属正常，能进到这步说明验签已过）"
W2=$(curl -s -o "$BK/hook2.txt" -w '%{http_code}' --noproxy '*' -m 10 -X POST -H "Host: $SITE_DOMAIN" -H 'X-GitHub-Event: push' -H 'X-Hub-Signature-256: sha256=deadbeef' --data-binary "@$BK/hook-body.json" http://127.0.0.1/_deploy)
ck '错签名被拒 403' "$([ "$W2" = 403 ] && echo 0 || echo 1)" "code=$W2 响应=$(head -c 60 "$BK/hook2.txt")"
W3=$(curl -s -o "$BK/hook3.txt" -w '%{http_code}' --noproxy '*' -m 10 -X POST -H "Host: $SITE_DOMAIN" -H 'X-GitHub-Event: push' -H "X-Hub-Signature-256: $SIG" --data-binary "@$BK/hook-body.json" http://127.0.0.1/_deploy)
ck '合法 push -> 202 并触发 deploy.sh' "$([ "$W3" = 202 ] && echo 0 || echo 1)" "code=$W3 响应=$(head -c 60 "$BK/hook3.txt")（sha 未变时应 no-op，见下一行）"
sleep 3; printf '接收器日志：\n'; journalctl -u blog-deploy-hook.service -n 6 --no-pager -o short-iso 2>/dev/null | sed 's/^/  /'

sec 'P12 收尾实况与待办'
printf '内存：'; free -m | awk '/^Mem:/{print "used "$3"M avail "$7"M"} /^Swap:/{print "｜ swap used "$3"M"}'
printf '监听：%s\n' "$(ss -ltn 2>/dev/null | awk 'NR>1{print $4}' | sort -u | tr '\n' ' ')"
printf '常驻服务数=%s\n' "$(systemctl list-units --type=service --state=running --no-legend 2>/dev/null | wc -l)"
printf 'release 列表=%s\n' "$(ls -1 /srv/blog/releases 2>/dev/null | sort -r | tr '\n' ' ')"
printf '软链 current -> %s\n' "$(readlink /srv/blog/current 2>/dev/null || echo 无)"
"$BIN/deploy.sh" --status | sed 's/^/  /'
systemctl list-timers --no-legend blog-poll.timer 2>/dev/null | awk '{print "  下次轮询 "$1" -> "$2}'
printf '\n下一步（人做的）：\n'
printf '  1) 备案接入生效前：域名公网维度不做验证（§0.2 K3）；分钟级更新已由 blog-poll.timer 承担\n'
printf '  2) 证书：在服务器上把 %s/dns-aliyun.ini 的 REPLACE_ME 换成 RAM AK/SK，然后跑\n     bash %s/deploy/install-stage2.sh --issue-cert\n' "$ETC" "$REPO"
printf '  3) 备案后：GitHub Settings -> Webhooks -> %s/_deploy，Content type raw，\n     密钥用 install-stage2.sh --show-secret 取；再把钩子网段加进 site.env 的 DEPLOY_ALLOW 并重跑本脚本\n' "https://$SITE_DOMAIN"
printf '\nSTAGE2-DONE pass=%s fail=%s note=%s\n' "$PASS" "$FAIL" "$NOTE"
exit 0
