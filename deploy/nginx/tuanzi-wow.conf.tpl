# 渲染结果：/etc/nginx/sites-available/tuanzi-wow.conf -> sites-enabled/
# 模板源：deploy/nginx/tuanzi-wow.conf.tpl   参数：/etc/blog/site.env
#
# 只在本文件定义 zone 与 map（http 上下文），HTTPS 块复用同名 zone，别在两个文件里重复定义。
# default_server 归 00-default 那个占位块（阶段 0 自己装的：只 listen default_server + server_name _ + return 404），本文件不抢
# server_name 命中；未被任何 server_name 命中的 Host（含乱扫 IP 的访问）一律 404，不会落到博客

limit_req_zone $binary_remote_addr zone=blog_req:2m rate=10r/s;
limit_req_zone $binary_remote_addr zone=deploy_req:2m rate=5r/s;

# HSTS 只在 HTTPS 下产出：值来自 $scheme，空字符串时 add_header 会自动不发这个头
map $scheme $blog_hsts {
    default '';
    https   'max-age=15768000';
}

server {
    listen 80;
    listen [::]:80;
    # 备案审核期（§0.2 K3）：域名 80 被云平台 403，只有 IP 直访能看到站点，
    # 所以 __IPSN__ 临时渲染成本机公网 IP；备案生效后把 site.env 的 IPSERVERNAME 置空并重跑安装脚本。
    server_name __DOMAIN__ __WWW____IPSN__;

    access_log /var/log/nginx/blog.access.log;
    error_log  /var/log/nginx/blog.error.log warn;

    __WWW301__
    include /etc/nginx/snippets/blog-locations.conf;
}
