# 渲染结果：/etc/nginx/sites-available/tuanzi-wow.ssl.conf -> sites-enabled/
# 模板源：deploy/nginx/tuanzi-wow.ssl.conf.tpl
# 只有证书签下来之后安装脚本才会启用本文件（nginx -t 不吃不存在的证书文件）
# 注意 http2：Ubuntu 22.04 的 nginx 1.18.0 没有「http2 on;」指令（那是 1.25.1+），必须写在 listen 上

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name __DOMAIN__ __WWW__;

    ssl_certificate     /etc/letsencrypt/live/__DOMAIN__/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/__DOMAIN__/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:blogSSL:2m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    access_log /var/log/nginx/blog-ssl.access.log;
    error_log  /var/log/nginx/blog-ssl.error.log warn;

    __WWW301__
    include /etc/nginx/snippets/blog-locations.conf;
}