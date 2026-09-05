# 渲染结果：/etc/nginx/snippets/blog-locations.conf （HTTP 与 HTTPS 两个 server 块共用，避免两份 location 漂移）
# 模板源：deploy/nginx/blog-locations.conf.tpl   参数：/etc/blog/site.env   别直接改渲染结果
#
# add_header 是「按块覆盖」而不是叠加：location 里只要出现 add_header，server 级的那几条就全丢。
# 所以安全头在每个 location 里各写一遍，不要「精简」到 server 级。
# 同理不写 expires：它会自动产出一个 Cache-Control，和下面的 add_header 撞成两个头。

root __ROOT__;
index index.html;
charset utf-8;
server_tokens off;
client_max_body_size 1m;

# 纵深防御：产物里本就没有这些，但别给误放文件留出口（放在最前，正则 location 先匹配者优先）
location ~ /(?:\.git|\.env|\.ssh|deploy\.sh|deploy-hook\.py) {
    deny all;
    access_log off;
}

error_page 404 /404.html;      # 产物里确有 404.html；别写 try_files $uri /index.html，缺文件会变成 500（§0.2 K8）

# 发布触发口：GitHub Webhook -> 这里 -> 127.0.0.1:9100（真正的门是 HMAC 验签，这层只是限流 + 来源白名单）
location = /_deploy {
    limit_req zone=deploy_req burst=10 nodelay;
    include /etc/nginx/snippets/blog-deploy-allow.conf;
    proxy_pass http://127.0.0.1:9100/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 15s;
    access_log /var/log/nginx/blog-deploy.access.log;
    add_header Cache-Control "no-store" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Strict-Transport-Security $blog_hsts always;
}

# 阶段 4 探活用（不查后端，只证明 nginx 与静态产物在）
location = /healthz-nginx {
    access_log off;
    default_type text/plain;
    add_header Cache-Control "no-store" always;
    return 200 "ok\n";
}

# 阶段 3 启用：检索与统计（只绑 127.0.0.1:8000，永不直接对公网）
# location /api/ {
#     limit_req zone=blog_req burst=20 nodelay;
#     proxy_pass http://127.0.0.1:8000;
#     proxy_http_version 1.1;
#     proxy_set_header Host $host;
#     proxy_set_header X-Real-IP $remote_addr;
#     proxy_set_header X-Forwarded-Proto $scheme;
# }

# 带扩展名的静态资源：Hugo --minify + fingerprint 后文件名含哈希，可放一年不可变
location ~* \.(?:css|js|mjs|map|png|jpe?g|gif|webp|avif|svg|ico|woff2?|ttf|eot|mp3|bundle)$ {
    limit_req zone=blog_req burst=40 nodelay;
    add_header Cache-Control "public, max-age=31536000, immutable" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Strict-Transport-Security $blog_hsts always;
    access_log off;
    try_files $uri =404;
}

# 页面：5 分钟内可复用，改内容最坏 5 min 后浏览器可见（服务端更新链路本身 < 60 s）
location / {
    limit_req zone=blog_req burst=20 nodelay;
    add_header Cache-Control "public, max-age=300" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Strict-Transport-Security $blog_hsts always;
    try_files $uri $uri/ =404;
}