#!/usr/bin/env bash
# 阶段 0 环境预备 S7：安装 Hugo 0.165.0 extended + 修复 certbot
# 用法：整段粘贴到阿里云 Workbench（root）。幂等，可重复执行，不打印任何凭据。
# 约定：所有下载都先校验 sha256 再落地，宁可不装也不装来路不明的二进制。
{
set +e
echo '##### S7-1 安装 Hugo 0.165.0 extended（境内加速源 -> 校验 -> GitHub 续传兜底）#####'
HV=0.165.0
PKG="hugo_extended_${HV}_linux-amd64.tar.gz"
GH="https://github.com/gohugoio/hugo/releases/download/v${HV}/${PKG}"
SIZE=21690586
EXPECT=f43494894cdf4a8630a201d5c828051c77f523cc66bb3938b30806835470ac20
mkdir -p /srv/blog/bin
if [ -x /srv/blog/bin/hugo ]; then
  echo "  hugo 已存在，跳过下载：$(/srv/blog/bin/hugo version 2>&1 | head -1)"
else
  OK=0
  for M in 'https://gh-proxy.com/' 'https://ghfast.top/' 'https://ghproxy.net/'; do
    echo "  加速源: ${M}"
    curl -4 -fL --connect-timeout 8 -m 300 -o /root/hugo.tar.gz "${M}${GH}" 2>/root/curl.err
    rc=$?
    sz=$(stat -c %s /root/hugo.tar.gz 2>/dev/null || echo 0)
    echo "    rc=${rc} size=${sz}/${SIZE}  $(tail -1 /root/curl.err 2>/dev/null | cut -c1-60)"
    if [ "$sz" -gt 21000000 ]; then
      got=$(sha256sum /root/hugo.tar.gz | cut -d' ' -f1)
      if [ "$got" = "$EXPECT" ]; then OK=1; echo '    sha256 校验通过'; break; fi
      echo "    sha256 不匹配（源可能被篡改/截断）got=${got}"; rm -f /root/hugo.tar.gz
    fi
  done
  if [ $OK -eq 0 ]; then
    echo '  加速源均未通过 -> GitHub 直连断点续传（最多 8 轮 x 240s）'
    for i in 1 2 3 4 5 6 7 8; do
      curl -4 -fL -C - --connect-timeout 8 -m 240 -o /root/hugo.tar.gz "$GH" 2>/dev/null; rc=$?
      sz=$(stat -c %s /root/hugo.tar.gz 2>/dev/null || echo 0)
      echo "    第 ${i} 轮 rc=${rc} 已下载 ${sz}/${SIZE}"
      [ $rc -eq 0 ] && break
    done
    got=$(sha256sum /root/hugo.tar.gz 2>/dev/null | cut -d' ' -f1)
    [ "$got" = "$EXPECT" ] && { OK=1; echo '    续传完成后 sha256 通过'; }
  fi
  if [ $OK -eq 1 ]; then
    tar -xzf /root/hugo.tar.gz -C /srv/blog/bin/ hugo && chmod 755 /srv/blog/bin/hugo
    chown blog:blog /srv/blog/bin/hugo
    ln -sfn /srv/blog/bin/hugo /usr/local/bin/hugo
    rm -f /root/hugo.tar.gz /root/curl.err
    echo "  安装完成：$(hugo version 2>&1 | head -1)"
  else
    echo '  !! Hugo 仍未装上：请改走 Workbench 的「文件上传」把本地 tar.gz 传到 /root 后再执行本段'
  fi
fi
echo '##### S7-2 certbot 现状诊断（上次用 head -1 把真实报错截掉了）#####'
echo '--- 当前解析到的可执行文件 ---'
command -v certbot
dpkg -l 2>/dev/null | grep -Ei 'certbot|python3-acme|python3-josepy|python3-openssl' | awk '{print "  "$2" "$3}'
echo '--- 完整报错（末尾 25 行）---'
certbot --version 2>&1 | tail -25 | sed 's/^/  /'
echo '--- /usr/local 下可能遮蔽系统 python 的包（仅列名，历史项目遗留）---'
ls /usr/local/lib/python3.10/dist-packages 2>/dev/null | sed 's/\(-[0-9].*\)\|\(\.dist-info\)\|\(\.egg-info\)$//' | sort -u | tr '\n' ' ' | cut -c1-1200
echo
echo '--- apt 通道是否正常（packagekit masked 只影响 command-not-found 助手，不应影响 apt）---'
apt-get update -qq >/root/aptu.log 2>&1; echo "  apt-get update rc=$?"; tail -4 /root/aptu.log | sed 's/^/  /'

echo '##### S7-3 certbot 隔离安装到 /opt/certbot（venv 天然不读被污染的 dist-packages）#####'
if [ ! -x /opt/certbot/bin/python ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y -qq python3-venv >/dev/null 2>&1
  python3 -m venv /opt/certbot >/root/venv.log 2>&1; rc=$?
  echo "  venv 创建 rc=${rc}"; tail -3 /root/venv.log | sed 's/^/  /'
  echo "  $(grep -o 'include-system-site-packages.*' /opt/certbot/pyvenv.cfg 2>/dev/null)"
else
  echo '  venv 已存在'
fi
PIP=/opt/certbot/bin/pip
if [ -x "$PIP" ]; then
  DONE=0
  for IDX in 'https://mirrors.cloud.aliyuncs.com/pypi/simple/' 'https://mirrors.aliyun.com/pypi/simple/' 'https://pypi.tuna.tsinghua.edu.cn/simple'; do
    HOST=$(echo "$IDX" | awk -F/ '{print $3}')
    echo "  pip 源: ${HOST}"
    "$PIP" install -q --upgrade pip -i "$IDX" --trusted-host "$HOST" --timeout 20 --retries 1 >/root/pip.log 2>&1
    "$PIP" install -q 'certbot>=2.0' certbot-nginx -i "$IDX" --trusted-host "$HOST" --timeout 20 --retries 1 >>/root/pip.log 2>&1
    if [ -x /opt/certbot/bin/certbot ]; then
      v=$(/opt/certbot/bin/certbot --version 2>&1 | tail -1)
      if echo "$v" | grep -qi 'certbot'; then DONE=1; echo "  成功于 ${HOST} -> $v"; break; fi
    fi
    echo "    未装上，末尾日志: $(tail -2 /root/pip.log | tr '\n' ' ' | cut -c1-140)"
  done
  if [ $DONE -eq 1 ]; then
    ln -sfn /opt/certbot/bin/certbot /usr/local/bin/certbot
    hash -r
    echo "  生效路径: $(command -v certbot)"
    echo "  版本: $(certbot --version 2>&1 | tail -1)"
    echo "  nginx 插件命中数: $(certbot plugins 2>&1 | grep -c nginx)"
  else
    echo '  !! venv 安装失败，回传 /root/pip.log 末尾内容'
    tail -12 /root/pip.log | sed 's/^/  /'
  fi
else
  echo '  !! python3 -m venv 不可用，先看 S7-2 的 apt rc'
fi

echo '##### S7-4 收尾复核 #####'
echo "  hugo: $(command -v hugo) -> $(hugo version 2>&1 | head -1)"
free -m | awk 'NR==1||/Mem|Swap/ {print "  "$0}'
swapon --show | sed 's/^/  /'
echo "  监听: $(ss -ltnH 2>/dev/null | awk "{print \$4}" | grep -oE '[0-9]+$' | sort -un | tr '\n' ' ')"
nginx -t 2>&1 | tail -2 | sed 's/^/  /'
for h in tuanzi-wow.cn www.tuanzi-wow.cn; do
  echo "  http://$h/ -> $(curl -4 -s -o /dev/null -w "code=%{http_code} time=%{time_total}s" -m 8 "http://$h/")"
done
echo '##### S7 结束：请把 S7-1~S7-4 全部输出回传 #####'
}