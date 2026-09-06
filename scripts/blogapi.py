#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""blogapi.py — 阶段 3 检索与统计服务（docs/plan.md 阶段 3.3~3.5，2026-09-06 设计定稿）。

由 systemd 拉起，只绑 127.0.0.1:8000（uvicorn --host 由单元文件指定），永不直对公网。
接口：
  GET  /api/search?q=&limit=   bm25 检索；摘要 <mark> 与锚点由 Python 对 sections 拼装
  POST /api/visit              sendBeacon 埋点 {u,r,v}，按 Asia/Shanghai 日聚合
  GET  /api/stats?days=7|30    PV/UV/逐日/热门页/来源站
  GET  /healthz                存活 + DB 可读 + 索引篇数 + current release 名
  POST /api/reindex            增量/全量重建；必须带 X-Reindex-Token（未配置 token 时一律 401）
依赖：fastapi、uvicorn、jieba；其余标准库（sqlite3 同步调用，单 worker 查询亚毫秒）。
路径可用环境变量 BLOGAPI_BASE / BLOGAPI_DB 覆盖（本地测试用），默认 /srv/blog。
"""

import html
import json
import logging
import os
import re
import sqlite3
import sys
import threading
import time
from datetime import datetime, timedelta
from urllib.parse import urlparse
from zoneinfo import ZoneInfo

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reindex as idx   # noqa: E402  索引核心（分词、库表、全量/增量）

from fastapi import FastAPI, HTTPException, Request, Response   # noqa: E402
from fastapi.responses import JSONResponse   # noqa: E402

BASE = os.environ.get('BLOGAPI_BASE', '/srv/blog')
CURRENT_DIR = os.path.join(BASE, 'current')
RELEASES_DIR = os.path.join(BASE, 'releases')
REINDEX_TOKEN = os.environ.get('REINDEX_TOKEN', '')
CN_TZ = ZoneInfo('Asia/Shanghai')
OWN_HOSTS = {'tuanzi-wow.cn', 'www.tuanzi-wow.cn'}   # 站内跳转不算「来源站」
MAX_BODY = 4096
RELEASE_NAME_RE = re.compile(r'\d{8}-\d{6}')

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
log = logging.getLogger('blogapi')

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)   # 不暴露 API 文档面
_reindex_lock = threading.Lock()   # deploy 与手工触发并发时串行化，后者等锁后自然 no-op/退全量


# ---------------------------------------------------------------- /api/search

def _match_expr(tokens, op):
    return (' %s ' % op).join('"%s"' % t.replace('"', '""') for t in tokens)


def _hit(conn, row, tokens):
    """命中一篇 → 对其 sections 逐节打分取最佳，Python 侧拼 <mark> 摘要。"""
    secs = conn.execute(
        'SELECT anchor, heading, text FROM sections WHERE post_id=? ORDER BY ord', (row['id'],)
    ).fetchall()
    low_tokens = sorted({t.lower() for t in tokens if len(t) >= 2}, key=len, reverse=True)
    best, best_score = None, 0
    for anchor, heading, text in secs:
        low = text.lower()
        score = sum(low.count(t) for t in low_tokens)
        if score > best_score:
            best, best_score = (anchor, heading, text), score
    if best is None and secs:
        best = (secs[0][0], secs[0][1], secs[0][2])   # 只有标题/分类命中 → 页首
    anchor, heading, snippet = '', '', ''
    if best:
        anchor, heading, snippet = best[0], best[1], _snippet(best[2], low_tokens)
    return {
        'url': row['url'],
        'title': row['title'],
        'categories': [c for c in (row['categories'] or '').split(',') if c],
        'tags': [t for t in (row['tags'] or '').split(',') if t],
        'anchor': anchor,
        'heading': heading,
        'snippet': snippet,
    }


def _snippet(text, low_tokens, lead=40, width=140):
    if not text:
        return ''
    low = text.lower()
    pos = -1
    for t in low_tokens:
        p = low.find(t)
        if p >= 0 and (pos < 0 or p < pos):
            pos = p
    if pos < 0:
        start, seg = 0, text[:width]
    else:
        start = max(0, pos - lead)
        seg = text[start:start + width]
    esc = html.escape(seg)
    if low_tokens:
        # 单遍替换：alternation 先长后短，避免 <mark> 标签被后续 token 二次命中
        pat = re.compile('|'.join(re.escape(t) for t in low_tokens), re.IGNORECASE)
        esc = pat.sub(lambda m: '<mark>%s</mark>' % m.group(0), esc)
    return ('…' if start > 0 else '') + esc + ('…' if start + len(seg) < len(text) else '')


@app.get('/api/search')
def api_search(q: str = '', limit: int = 10):
    t0 = time.perf_counter()
    q = (q or '').strip()[:100]
    limit = max(1, min(20, limit))
    hits, total = [], 0
    tokens = idx.query_tokens(q) if q else []
    if tokens:
        conn = idx.connect()
        try:
            def ids(expr):
                return [r[0] for r in conn.execute(
                    'SELECT rowid FROM posts_fts WHERE posts_fts MATCH ? ORDER BY rank LIMIT 50',
                    (_match_expr(tokens, expr),))]

            found = ids('AND')
            if not found:
                found = ids('OR')
            total = len(found)
            if found:
                found = found[:limit]
                marks = ','.join('?' * len(found))
                rows = conn.execute(
                    'SELECT id, url, title, categories, tags FROM posts WHERE id IN (%s)' % marks, found
                ).fetchall()
                by_id = {r['id']: r for r in rows}
                hits = [_hit(conn, by_id[i], tokens) for i in found if i in by_id]
        finally:
            conn.close()
    return {'q': q, 'total': total, 'took_ms': round((time.perf_counter() - t0) * 1000, 2), 'hits': hits}


# ---------------------------------------------------------------- /api/visit

@app.post('/api/visit')
async def api_visit(request: Request):
    body = await request.body()
    if len(body) > MAX_BODY:
        return Response(status_code=204)
    try:
        d = json.loads(body.decode('utf-8', 'replace')) if body else {}
    except Exception:
        d = {}
    if not isinstance(d, dict):
        d = {}
    u = str(d.get('u') or '')
    if not u.startswith('/'):        # 只记站内路径，拒绝外站地址污染
        return Response(status_code=204)
    u = u.split('#', 1)[0].split('?', 1)[0][:200]
    ref = str(d.get('r') or '')[:300]
    vid = re.sub(r'[^0-9A-Za-z_-]', '', str(d.get('v') or ''))[:64]
    day = datetime.now(CN_TZ).strftime('%Y-%m-%d')
    host = ''
    if ref:
        try:
            h = (urlparse(ref).hostname or '').lower()
            if h and h not in OWN_HOSTS:
                host = h[:100]
        except ValueError:
            pass
    conn = idx.connect()
    try:
        with conn:
            conn.execute(
                'INSERT INTO visit(day,url,count) VALUES(?,?,1) '
                'ON CONFLICT(day,url) DO UPDATE SET count=count+1', (day, u))
            if vid:
                conn.execute('INSERT OR IGNORE INTO visit_uv(day,vid) VALUES(?,?)', (day, vid))
            if host:
                conn.execute(
                    'INSERT INTO visit_ref(day,host,count) VALUES(?,?,1) '
                    'ON CONFLICT(day,host) DO UPDATE SET count=count+1', (day, host))
    finally:
        conn.close()
    return Response(status_code=204)


# ---------------------------------------------------------------- /api/stats

@app.get('/api/stats')
def api_stats(days: int = 7):
    days = max(1, min(30, days))
    today = datetime.now(CN_TZ).date()
    start = today - timedelta(days=days - 1)
    s, e = start.isoformat(), today.isoformat()
    rng = (s, e)
    conn = idx.connect()
    try:
        pv = conn.execute('SELECT COALESCE(SUM(count),0) FROM visit WHERE day BETWEEN ? AND ?', rng).fetchone()[0]
        uv = conn.execute('SELECT COUNT(*) FROM visit_uv WHERE day BETWEEN ? AND ?', rng).fetchone()[0]
        pv_day = {r[0]: r[1] for r in conn.execute(
            'SELECT day, SUM(count) FROM visit WHERE day BETWEEN ? AND ? GROUP BY day', rng)}
        uv_day = {r[0]: r[1] for r in conn.execute(
            'SELECT day, COUNT(*) FROM visit_uv WHERE day BETWEEN ? AND ? GROUP BY day', rng)}
        top = conn.execute(
            'SELECT url, SUM(count) c FROM visit WHERE day BETWEEN ? AND ? GROUP BY url ORDER BY c DESC LIMIT 10', rng
        ).fetchall()
        refs = conn.execute(
            'SELECT host, SUM(count) c FROM visit_ref WHERE day BETWEEN ? AND ? GROUP BY host ORDER BY c DESC LIMIT 10', rng
        ).fetchall()
    finally:
        conn.close()
    series = []
    for i in range(days):
        d = (start + timedelta(days=i)).isoformat()
        series.append({'day': d, 'pv': int(pv_day.get(d, 0)), 'uv': int(uv_day.get(d, 0))})
    return {
        'days': days, 'pv': int(pv), 'uv': int(uv),
        'series': series,
        'top': [{'url': r[0], 'pv': int(r[1])} for r in top],
        'refs': [{'host': r[0], 'pv': int(r[1])} for r in refs],
    }


# ---------------------------------------------------------------- /healthz

@app.get('/healthz')
def healthz():
    try:
        conn = idx.connect()
        try:
            posts = conn.execute('SELECT COUNT(*) FROM posts').fetchone()[0]
        finally:
            conn.close()
    except sqlite3.Error as e:
        return JSONResponse(status_code=503, content={'status': 'error', 'error': str(e)[:200]})
    release = ''
    try:
        release = os.path.basename(os.path.realpath(CURRENT_DIR))
    except OSError:
        pass
    return {'status': 'ok', 'posts': posts, 'release': release}


# ---------------------------------------------------------------- /api/reindex

def _release_name(v):
    v = str(v or '')
    return v if RELEASE_NAME_RE.fullmatch(v) else ''   # 只认 deploy.sh 的目录名格式，防路径穿越


@app.post('/api/reindex')
async def api_reindex(request: Request):
    if not REINDEX_TOKEN or request.headers.get('x-reindex-token', '') != REINDEX_TOKEN:
        raise HTTPException(status_code=401, detail='reindex 需要 X-Reindex-Token')
    body = await request.body()
    if len(body) > MAX_BODY:
        raise HTTPException(status_code=413, detail='body 过大')
    try:
        d = json.loads(body.decode('utf-8', 'replace')) if body else {}
    except Exception:
        d = {}
    if not isinstance(d, dict):
        d = {}
    prev, cur = _release_name(d.get('prev')), _release_name(d.get('cur'))
    with _reindex_lock:
        cur_dir = os.path.join(RELEASES_DIR, cur) if cur else None
        prev_dir = os.path.join(RELEASES_DIR, prev) if prev else None
        if cur_dir and os.path.isdir(cur_dir) and prev_dir and os.path.isdir(prev_dir):
            out = idx.incremental(prev_dir, cur_dir, release=cur)
        else:
            # prev 缺失（首次/回滚后）或目录名不合法 → 全量，解析 current 实际指向
            out = idx.full_rebuild(os.path.realpath(CURRENT_DIR), release=cur)
    log.info('reindex: %s', json.dumps(out, ensure_ascii=False))
    return out


if __name__ == '__main__':
    import uvicorn
    uvicorn.run(app, host='127.0.0.1', port=int(os.environ.get('BLOGAPI_PORT', '8000')))
