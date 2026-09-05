#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""deploy-hook.py — 阶段 2.2 GitHub Webhook 接收器（单文件，仅标准库）。

为什么不用 FastAPI/Uvicorn：本服务只有一个路由、无数据库、无并发业务，
标准库常驻约 15 MB，FastAPI+Uvicorn 约 180 MB；1.6 GiB 机器上省下的都留给阶段 3 检索层。
（docs/plan.md §2.2 原文即允许「FastAPI 或标准库 http.server」二选一。）

安全边界：
  * 只绑 127.0.0.1:9100；公网必须经 nginx 反代 /_deploy（另有 limit_req 与来源白名单）
  * 校验 X-Hub-Signature-256 = sha256=HMAC(secret, 原始 body)，定长比较
  * 只接受 X-GitHub-Event: push 且 ref == refs/heads/main；其余回 200 ignored（免得 GitHub 一直重试）
  * 验签失败 403、body 过大/缺失 413、路径不对 404，都不触发发布
  * 「有没有新内容」由 deploy.sh 比对 sha 决定，所以重复投递天然幂等
  * 收到即回 202，构建在后台线程跑（GitHub 的投递超时是 10 s，构建可能要 30 s）

用法：
  deploy-hook.py [--host 127.0.0.1] [--port 9100]
                 [--secret-file /etc/blog/webhook-secret]
                 [--deploy /srv/blog/bin/deploy.sh] [--ref refs/heads/main]
  deploy-hook.py --sign-body FILE      # 只对 FILE 内容算一次签名并打印，用于自检
"""
import argparse
import hashlib
import hmac
import json
import os
import shlex
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STATE = {"running": False, "last": "startup", "accepted": 0, "ignored": 0, "rejected": 0}
TRIGGER_LOCK = threading.Lock()
CFG = {}


def log(msg):
    print("%s %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg), flush=True)


def signature(secret, body):
    return "sha256=" + hmac.new(secret, body, hashlib.sha256).hexdigest()


def read_secret(path):
    try:
        with open(path, "rb") as fh:
            raw = fh.read().strip()
    except OSError as exc:
        log("FATAL 读不到签名密钥 %s：%s" % (path, exc))
        sys.exit(2)
    if len(raw) < 16:
        log("FATAL 签名密钥过短（%d 字节），拒绝启动" % len(raw))
        sys.exit(2)
    return raw


def run_deploy(head):
    t0 = time.time()
    try:
        proc = subprocess.run(CFG["deploy"], stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, timeout=CFG["deploy_timeout"])
        tail = (proc.stdout or b"").decode("utf-8", "replace").strip()[-400:]
        STATE["last"] = "rc=%s %s" % (proc.returncode, tail or "-")
        log("deploy 结束 rc=%s 耗时=%.1fs head=%s" % (proc.returncode, time.time() - t0, head))
    except subprocess.TimeoutExpired:
        STATE["last"] = "timeout after %ss" % CFG["deploy_timeout"]
        log("deploy 超时（%s s），子进程已被杀死" % CFG["deploy_timeout"])
    except Exception as exc:  # noqa: BLE001 - 任何异常都不能带走常驻服务
        STATE["last"] = "error %r" % (exc,)
        log("deploy 启动失败：%r" % (exc,))
    finally:
        STATE["running"] = False
        TRIGGER_LOCK.release()


class Handler(BaseHTTPRequestHandler):
    server_version = ""
    sys_version = ""
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        log("http " + (fmt % args))

    def _reply(self, code, text):
        body = text.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.split("?", 1)[0].rstrip("/") in ("", "/healthz"):
            payload = {"ok": True, "deploying": STATE["running"], "last": STATE["last"],
                       "accepted": STATE["accepted"], "ignored": STATE["ignored"],
                       "rejected": STATE["rejected"], "ref": CFG["ref"]}
            self.send_response(200)
            raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(raw)
        else:
            self._reply(404, "not found")

    def do_POST(self):
        path = self.path.split("?", 1)[0].rstrip("/")
        if path not in ("", "/_deploy"):
            return self._reply(404, "not found")
        try:
            length = int(self.headers.get("Content-Length") or "-1")
        except ValueError:
            length = -1
        if length < 0 or length > CFG["max_body"]:
            STATE["rejected"] += 1
            return self._reply(413, "body missing or too large")
        body = self.rfile.read(length)
        got = self.headers.get("X-Hub-Signature-256", "")
        if not hmac.compare_digest(got, signature(CFG["secret"], body)):
            STATE["rejected"] += 1
            log("REJECT 验签失败 来自 %s" % self.client_address[0])
            return self._reply(403, "invalid signature")
        if self.headers.get("X-GitHub-Event", "") != "push":
            STATE["ignored"] += 1
            return self._reply(200, "ignored: event=%s" % self.headers.get("X-GitHub-Event", "?"))
        try:
            payload = json.loads(body.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            return self._reply(400, "body is not json")
        ref = payload.get("ref") or ""
        if ref != CFG["ref"] or payload.get("deleted") is True:
            STATE["ignored"] += 1
            return self._reply(200, "ignored: ref=%s deleted=%s" % (ref, payload.get("deleted")))
        head = (payload.get("after") or "")[:7]
        if not TRIGGER_LOCK.acquire(blocking=False):
            return self._reply(202, "accepted: 已有发布在跑，本次不重复触发")
        STATE["running"] = True
        STATE["accepted"] += 1
        try:
            threading.Thread(target=run_deploy, args=(head,), daemon=True).start()
        except Exception as exc:  # noqa: BLE001 - 起线程失败必须立刻放锁，否则永久拒绝触发
            STATE["running"] = False
            TRIGGER_LOCK.release()
            log("无法启动发布线程：%r" % (exc,))
        log("ACCEPT push head=%s" % head)
        return self._reply(202, "accepted")


def main():
    ap = argparse.ArgumentParser(description="GitHub webhook receiver (stdlib only)")
    ap.add_argument("--host", default="127.0.0.1", help="只应绑回环")
    ap.add_argument("--port", type=int, default=9100)
    ap.add_argument("--secret-file", default="/etc/blog/webhook-secret")
    ap.add_argument("--deploy", default="/srv/blog/bin/deploy.sh", help="验签通过后执行的命令")
    ap.add_argument("--ref", default="refs/heads/main")
    ap.add_argument("--max-body", type=int, default=1048576)
    ap.add_argument("--deploy-timeout", type=int, default=600)
    ap.add_argument("--sign-body", help="只对给定文件算签名并打印（自检用，不启动服务）")
    args = ap.parse_args()

    secret = read_secret(args.secret_file)
    if args.sign_body:
        with open(args.sign_body, "rb") as fh:
            print(signature(secret, fh.read()))
        return 0

    CFG.update(secret=secret, deploy=shlex.split(args.deploy), ref=args.ref,
               max_body=args.max_body, deploy_timeout=args.deploy_timeout)
    if len(CFG["deploy"]) == 0:
        log("FATAL --deploy 为空")
        sys.exit(2)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.daemon_threads = True
    log("监听 %s:%s ref=%s deploy=%s" % (args.host, args.port, args.ref, " ".join(CFG["deploy"])))
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()