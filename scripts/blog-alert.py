#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""blog-alert — 阶段 4.2/4.3 告警发送器（QQ SMTP 465/SSL；安装到 /usr/local/bin/blog-alert）。

用法：blog-alert "消息"   （参数为正文首行；stdin 若有内容则附加为正文）
凭据：/etc/blog/blog-alert.env（0600，root）——MAIL_FROM / MAIL_TO / SMTP_USER / SMTP_PASS
      SMTP_PASS 用 QQ 邮箱「授权码」，不是登录密码；阿里云封 25 出站，走 465/SSL（§0.2 K9）。
行为：凭据缺失或含 REPLACE_ME → exit 3（不发送，调用方自行决定是否静默）；
      SMTP 失败 → exit 1 并落 syslog；成功 → exit 0，只落一行 syslog，不打印凭据。
deploy.sh 的 alert() 已预留调用本命令（不存在则静默跳过）。
"""

import os
import smtplib
import sys
from email.header import Header
from email.mime.text import MIMEText
from socket import gethostname

ENV_PATH = os.environ.get('BLOG_ALERT_ENV', '/etc/blog/blog-alert.env')
SMTP_HOST = 'smtp.qq.com'
SMTP_PORT = 465


def load_env(path):
    env = {}
    try:
        with open(path, encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#') or '=' not in line:
                    continue
                k, _, v = line.partition('=')
                env[k.strip()] = v.strip()
    except OSError:
        pass
    return env


def main():
    env = load_env(ENV_PATH)
    user, password = env.get('SMTP_USER', ''), env.get('SMTP_PASS', '')
    mail_to = env.get('MAIL_TO') or user
    mail_from = env.get('MAIL_FROM') or user
    if not user or not password or 'REPLACE_ME' in (user + password):
        print('blog-alert: 凭据未配置（%s 缺 SMTP_USER/SMTP_PASS 或含 REPLACE_ME），不发送' % ENV_PATH,
              file=sys.stderr)
        return 3

    first_line = ' '.join(sys.argv[1:]).strip()
    extra = ''
    if not sys.stdin.isatty():
        try:
            extra = sys.stdin.read().strip()
        except Exception:
            extra = ''
    body_text = '\n'.join(x for x in (first_line, extra) if x) or '(空消息)'
    subject = '[blog@%s] %s' % (gethostname(), first_line[:60] if first_line else '通知')

    msg = MIMEText(body_text, 'plain', 'utf-8')
    msg['Subject'] = Header(subject, 'utf-8')
    msg['From'] = mail_from
    msg['To'] = mail_to

    try:
        with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, timeout=20) as s:
            s.login(user, password)
            s.sendmail(mail_from, [mail_to], msg.as_string())
    except Exception as e:
        os.system("logger -t blog-alert 'SMTP 发送失败: %s' 2>/dev/null" % type(e).__name__)
        print('blog-alert: SMTP 发送失败：%s: %s' % (type(e).__name__, str(e)[:120]), file=sys.stderr)
        return 1
    os.system("logger -t blog-alert 'alert sent: %s' 2>/dev/null" % first_line[:60].replace("'", ''))
    return 0


if __name__ == '__main__':
    sys.exit(main())
