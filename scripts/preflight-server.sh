#!/usr/bin/env bash
# 开发前置检查（云主机侧）。在 ECS 上以 root 运行：bash preflight-server.sh
# 只读探测 + 安装建议，不改动任何配置。凭据一律不得写入本文件。
DOMAIN="${1:-tuanzi-wow.cn}"
pass(){ printf '  [PASS] %-26s %s\n' "$1" "$2"; }
warn(){ printf '  [WARN] %-26s %s\n' "$1" "$2"; }
fail(){ printf '  [FAIL] %-26s %s\n' "$1" "$2"; }

echo '== 1. 系统资源 =='
. /etc/os-release; echo "  OS: $PRETTY_NAME | 内核 $(uname -r)"
cpu=$(nproc); mem=$(awk '/MemTotal/{printf "%.0f", $2/1024}' /proc/meminfo)
swp=$(awk '/SwapTotal/{printf "%.0f", $2/1024}' /proc/meminfo)
echo "  CPU 核数: $cpu   内存: ${mem}MB   swap: ${swp}MB"
[ "$cpu" -ge 2 ] && pass "cpu" "${cpu} 核" || fail "cpu" "不足 2 核"
[ "$mem" -ge 1800 ] && pass "memory" "${mem}MB" || warn "memory" "${mem}MB 偏低"
if [ "$swp" -lt 1024 ]; then fail "swap" "${swp}MB（必须 >=2G，否则 Hugo 构建尖峰会 OOM 掉 Uvicorn）"
  echo '         fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile'
  echo '         echo "/swapfile none swap sw 0 0" >> /etc/fstab && sysctl vm.swappiness=10'
else pass "swap" "${swp}MB"; fi
df -h / | awk 'NR==2{print "  磁盘 /: 已用 "$3" / "$2" ("$5")"; if (int($5)>80) print "  [WARN] 根分区使用率过高"; }'
free -h | sed 's/^/    /'
echo "  负载: $(cat /proc/loadavg)   systemd: $(systemctl --version | head -1)"

echo '== 2. 时区与时间同步（影响证书校验与日志） =='
timedatectl 2>/dev/null | sed 's/^/    /'
timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q yes && pass "ntp" "已同步" || fail "ntp" "未同步（apt install chrony 或 timedatectl set-ntp true）"

echo '== 3. 监听端口与对外暴露 =='
ss -tlnp 2>/dev/null | awk 'NR>1{print "    "$4"  "$6}' | sort -u
echo "  说明: 部署后对外只应有 22/80/443；9100(webhook) 与 8000(FastAPI) 必须只绑 127.0.0.1"

echo '== 4. SSH 加固 =='
sshd -T 2>/dev/null | awk '/^(permitrootlogin|passwordauthentication|port |pubkeyauthentication|maxauthtries)/{print "    "$0}'
pa=$(sshd -T 2>/dev/null | awk '/^passwordauthentication/{print $2}')
pr=$(sshd -T 2>/dev/null | awk '/^permitrootlogin/{print $2}')
[ "$pa" = "no" ] && pass "密码登录" "已禁用" || fail "密码登录" "仍开启（改密钥登录后设 PasswordAuthentication no）"
[ "$pr" = "no" ] || [ "$pr" = "prohibit-password" ] && pass "root 登录" "$pr" || warn "root 登录" "$pr（建议建 blog 用户 + prohibit-password）"

echo '== 5. 主机防火墙（与阿里云安全组叠加） =='
if command -v firewall-cmd >/dev/null && firewall-cmd --state 2>/dev/null | grep -q running
then pass "firewalld" "运行中"; firewall-cmd --list-ports | sed 's/^/    ports: /'
elif iptables -S 2>/dev/null | grep -q 'DROP\|REJECT'; then warn "iptables" "存在规则，需确认 80/443 已放行"; iptables -S | head -20 | sed 's/^/    /'
else pass "iptables" "无拦截规则（由安全组控制即可）"; fi

echo '== 6. 依赖与包管理 =='
pm=''; command -v apt-get >/dev/null && pm=apt || { command -v yum >/dev/null && pm=yum; }
echo "  包管理器: $pm   （阿里云大陆可用内网源 mirrors.cloud.aliyuncs.com，无需代理）"
for c in git nginx hugo python3 pip3 certbot curl fail2ban-server systemctl; do
  if command -v "$c" >/dev/null; then p=$(command -v "$c"); [ "$c" = hugo ] && p="$($c version | head -1)"; pass "$c" "$p"; else warn "$c" "未安装"; fi
done
echo '  Hugo 安装（大陆建议直接用 GitHub release 的 extended 包，或配代理）：'
echo '    curl -L -o hugo.tar.gz https://github.com/gohugoio/hugo/releases/download/v0.147.9/hugo_extended_0.147.9_linux-amd64.tar.gz'
echo '    tar xzf hugo.tar.gz && install -m755 hugo /usr/local/bin/hugo && hugo version'

echo '== 7. 出网能力（决定更新链路能否成立） =='
t0=$(date +%s%N)
if curl -fsS --max-time 20 -o /dev/null https://github.com/ ; then
  t1=$(date +%s%N); pass "github.com" "可达，握手 $(( (t1-t0)/1000000 ))ms"
else fail "github.com" "不可达 -> 更新链路需改用 Gitee 镜像双源拉取"; fi
t0=$(date +%s%N)
if git ls-remote "https://github.com/${REPO:-chenghaoning51/OnMyWay}.git" >/dev/null 2>&1; then
  t1=$(date +%s%N); pass "git ls-remote" "认证/网络 OK $(( (t1-t0)/1000000 ))ms"
else warn "git ls-remote" "失败：公开仓库不应失败，多为跨境抖动，需重试与兜底 timer"; fi
if curl -s --max-time 8 -o /dev/null "https://raw.githubusercontent.com/" ; then pass "raw.githubusercontent" "可达" else warn "raw.githubusercontent" "大陆常不可达 -> 站点内禁止引用 GitHub raw 链接"
fi

echo '== 8. 邮件告警通道（阿里云封 25 端口出站） =='
for port in 465 587 25; do
  if timeout 5 bash -c "echo > /dev/tcp/smtp.qq.com/$port" 2>/dev/null
  then pass "smtp.qq.com:$port" "可连通"
  else [ "$port" = 25 ] && pass "smtp.qq.com:25" "不通（预期，阿里云封出站）" || fail "smtp.qq.com:$port" "不通 -> 告警发不出去，需查安全组出方向"
  fi
done

echo '== 9. 域名与备案可达性 =='
resolved=$(getent hosts "$DOMAIN" | awk '{print $1}' | head -1)
if [ -n "$resolved" ]; then
  pass "DNS" "$DOMAIN -> $resolved"
  [ "$(hostname -I | tr ' ' '\n' | grep -c "^$resolved$")" = "1" ] && pass "指向本机" "是（80/443 应可对外服务）" || warn "指向本机" "解析到 $resolved，非本机 IP -> A 记录待改"
  if curl -fsS --max-time 10 -o /dev/null "http://$DOMAIN/"; then pass "80 端口对外" "可访问（备案与接入商策略正常）"
  else warn "80 端口对外" "不可访问：未部署属正常；若 Nginx 已运行仍不通，则是备案/安全组问题"; fi
else fail "DNS" "$DOMAIN 无解析记录 -> 云解析加 A 记录"; fi

echo '== 10. 部署目录与用户 =='
id blog >/dev/null 2>&1 && pass "blog 用户" "已存在" || warn "blog 用户" "未创建 -> useradd -m -s /bin/bash blog && mkdir -p /srv/blog && chown -R blog:blog /srv/blog"
[ -d /srv/blog ] && pass "/srv/blog" "存在" || warn "/srv/blog" "不存在（阶段 2 创建）"
echo '  预期布局: /srv/blog/{src, releases, current->releases/<ts>, bin}'

echo '== 11. systemd 单元骨架（阶段 2 写入） =='
echo '  blog-deploy.service (Type=oneshot, User=blog, ExecStart=/srv/blog/bin/deploy.sh)'
echo '  blog-deploy.path / blog-poll.timer (OnUnitActiveSec=60s, RandomizedDelaySec=5)'
echo '  blog-webhook.service (User=blog, ExecStart=.../uvicorn --host 127.0.0.1 --port 9100)'
echo '  blog-api.service     (MemoryMax=400M, Restart=always, RuntimeMaxSec=86400)'
echo '  blog-backup.timer (03:30)   blog-health.timer (OnUnitActiveSec=5min)'

echo '== 完成。请回传本脚本输出，用于确认阶段 0 是否可关闭 =='