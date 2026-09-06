#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""reindex.py — 阶段 3 索引核心（docs/plan.md 阶段 3.1/3.2，2026-09-06 设计定稿）。

索引源 = current 的渲染 HTML：URL 取 canonical、锚点用 Goldmark 自动 id、
跳过 Chroma 行号单元（class=lnt/ln）——不解析 markdown，免复刻 Hugo 的中文路由与 slug 规则。
全量：python3 reindex.py --full [--root DIR]
增量：python3 reindex.py --cur <release名> [--prev <release名>]（两版 release 的文件差集）
库表：posts + posts_fts(external content, 触发器同步) + sections + visit/visit_uv/visit_ref
路径可用环境变量 BLOGAPI_BASE / BLOGAPI_DB 覆盖（本地测试用），默认 /srv/blog 与其下 data/search.db。
依赖：jieba；其余标准库。
"""

import argparse
import hashlib
import json
import os
import re
import sqlite3
import sys
from datetime import datetime
from functools import lru_cache
from html.parser import HTMLParser
from urllib.parse import urlparse

BASE = os.environ.get('BLOGAPI_BASE', '/srv/blog')
DB_PATH = os.environ.get('BLOGAPI_DB', os.path.join(BASE, 'data', 'search.db'))
RELEASES_DIR = os.path.join(BASE, 'releases')
CURRENT_DIR = os.path.join(BASE, 'current')

WORD_RE = re.compile(r'\w', re.UNICODE)
PAPERMOD_POST_MARK = b'post-single'   # PaperMod d376885 单页布局的判定标记（minify 后无引号也在）
BLOCK_TAGS = {
    'p', 'div', 'li', 'tr', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
    'pre', 'table', 'ul', 'ol', 'blockquote', 'section', 'article',
    'header', 'footer', 'figure', 'figcaption', 'br', 'td', 'th',
}
SKIP_TAGS = {'script', 'style', 'svg', 'template'}   # head 不能跳：canonical 在里面；head 内其他文本无处累积，自然丢弃
SKIP_CLASSES = {'lnt', 'ln', 'anchor'}                       # Chroma 行号单元 + 标题锚点链接（只产 '#' 文本）


def _norm_text(s):
    return re.sub(r'\s+', ' ', s).strip()


# ---------------------------------------------------------------- jieba（惰性加载，首次约 +60MB RSS）

_jieba = None


def jieba_mod():
    global _jieba
    if _jieba is None:
        import logging as _logging
        import jieba as _j
        _j.setLogLevel(_logging.CRITICAL)   # 别让 "Building prefix dict" 刷进 journald
        _j.initialize()
        _jieba = _j
    return _jieba


def tokenize(text):
    """索引侧分词：jieba 精确模式。"""
    if not text:
        return []
    return [t for t in jieba_mod().lcut(text) if t.strip()]


def query_tokens(q):
    """查询侧分词：cut_for_search 提高召回；只留含词字符的 token，去重保序。"""
    out, seen = [], set()
    for t in jieba_mod().cut_for_search(q):
        t = t.strip()
        if t and len(t) <= 40 and WORD_RE.search(t) and t not in seen:
            seen.add(t)
            out.append(t)
    return out[:20]


def build_words(title, categories, tags, section_texts):
    """词列 = 标题×3（bm25 提权）+ 分类/标签 + 正文，全部 jieba 预分词、空格分隔。"""
    parts = tokenize(title) * 3
    for s in (categories, tags):
        parts += tokenize(s.replace(',', ' ').replace('，', ' '))
    for t in section_texts:
        parts += tokenize(t)
    return ' '.join(t for t in parts if WORD_RE.search(t) and len(t) <= 40)


# ---------------------------------------------------------------- HTML 解析

class PageParser(HTMLParser):
    """从单篇渲染 HTML 提取 canonical/title/categories/tags/分节文本。

    只认 PaperMod 单页布局的标记：article.post-single 判定、h1.post-title、
    div.post-content 正文（h1-h6 的 id 为节锚点）、nav.breadcrumbs 分区链（首个 a
    是「首页」，取其后为分类）、ul.post-tags 标签链。
    """

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.canonical = ''
        self.title = ''
        self.is_post = False
        self.categories = []
        self.tags = []
        self.sections = []          # [(anchor, heading, text)]
        self._skip_stack = []
        self._in_content = False
        self._content_enter_depth = 0
        self._div_depth = 0
        self._chunks = []
        self._anchor = ''
        self._heading = ''
        self._heading_buf = []
        self._heading_tag = None
        self._in_title = False
        self._bc_list = None        # breadcrumbs 活跃时为 list
        self._bc_cur = None         # 当前 <a> 的文本槽
        self._tag_list = None
        self._tag_cur = None

    @staticmethod
    def _classes(attrs):
        for k, v in attrs:
            if k == 'class' and v:
                return v.split()
        return ()

    def handle_starttag(self, tag, attrs):
        cls = self._classes(attrs)
        if self._skip_stack:
            if tag in self._skip_stack:
                self._skip_stack.append(tag)   # 同名嵌套才需要配对；lnt/script 等不会出现
            return
        if tag in SKIP_TAGS or set(cls) & set(SKIP_CLASSES):
            if tag not in ('br', 'img', 'input', 'hr', 'meta', 'link'):
                self._skip_stack.append(tag)
            return
        d = {}
        for k, v in attrs:
            d.setdefault(k, v)

        if tag == 'link' and 'canonical' in (d.get('rel') or '') and d.get('href'):
            self.canonical = d['href']
        elif tag == 'article' and 'post-single' in cls:
            self.is_post = True
        elif tag == 'h1' and 'post-title' in cls and not self.title:
            self._in_title = True
        elif tag == 'nav' and 'breadcrumbs' in cls:
            self._bc_list = []
        elif tag == 'ul' and 'post-tags' in cls:
            self._tag_list = []

        if self._bc_list is not None and tag == 'a':
            self._bc_cur = ''
        if self._tag_list is not None and tag == 'a':
            self._tag_cur = ''

        if tag == 'div':
            if self._in_content:
                self._div_depth += 1
            elif 'post-content' in cls:
                self._in_content = True
                self._content_enter_depth = self._div_depth
                self._div_depth += 1
        if self._in_content:
            if tag in BLOCK_TAGS:
                self._chunks.append(' ')
            if tag in ('h1', 'h2', 'h3', 'h4', 'h5', 'h6'):
                self._flush_section()
                self._heading_tag = tag
                self._anchor = d.get('id') or ''
                self._heading_buf = []

    def handle_endtag(self, tag):
        if self._skip_stack:
            if tag == self._skip_stack[-1]:
                self._skip_stack.pop()
            return
        if tag == 'div' and self._in_content:
            self._div_depth -= 1
            if self._div_depth <= self._content_enter_depth:
                self._in_content = False
                self._flush_section()
                return
        if self._in_content and tag in BLOCK_TAGS:
            self._chunks.append(' ')
        if tag == 'h1' and self._in_title:
            self._in_title = False
        if self._heading_tag == tag:
            self._heading = _norm_text(''.join(self._heading_buf)).replace('#', '').strip()
            self._heading_tag = None
        if tag == 'a':
            if self._bc_cur is not None:
                t = _norm_text(self._bc_cur)
                if t:
                    self._bc_list.append(t)
                self._bc_cur = None
            if self._tag_cur is not None:
                t = _norm_text(self._tag_cur)
                if t and t not in self.tags:
                    self.tags.append(t)
                self._tag_cur = None
        if tag == 'nav' and self._bc_list is not None:
            # 第一个 a 是 i18n 的「首页」，其余为分区祖先链 → 作为分类
            self.categories = self._bc_list[1:] if len(self._bc_list) > 1 else self._bc_list
            self._bc_list = None
        if tag == 'ul' and self._tag_list is not None:
            self._tag_list = None

    def handle_data(self, data):
        if self._skip_stack:
            return
        if self._in_title:
            self.title += data
            return
        if self._bc_cur is not None:
            self._bc_cur += data
            return
        if self._tag_cur is not None:
            self._tag_cur += data
            return
        if self._in_content:
            if self._heading_tag:
                self._heading_buf.append(data)
            self._chunks.append(data)

    def _flush_section(self):
        text = _norm_text(''.join(self._chunks))
        self._chunks = []
        if text or self._anchor:
            self.sections.append((self._anchor, self._heading, text))
        self._anchor = ''
        self._heading = ''

    def result(self):
        self._flush_section()
        sections = [s for s in self.sections if s[2]]
        url = ''
        if self.canonical:
            url = urlparse(self.canonical).path
        return {
            'url': url,
            'title': _norm_text(self.title),
            'categories': ','.join(self.categories),
            'tags': ','.join(self.tags),
            'sections': sections,
        }


@lru_cache(maxsize=512)
def _parse_cached(abspath, mtime):
    """进程内 LRU 解析缓存，键 (path, mtime)（plan 3.4）。只读返回值。"""
    with open(abspath, 'rb') as f:
        raw = f.read()
    if PAPERMOD_POST_MARK not in raw:
        return None
    parser = PageParser()
    parser.feed(raw.decode('utf-8', 'replace'))
    parser.close()
    if not parser.is_post:
        return None
    return parser.result()


def parse_page(abspath):
    st = os.stat(abspath)
    pg = _parse_cached(abspath, st.st_mtime)
    if pg is None:
        return None
    pg = dict(pg)
    pg['mtime'] = datetime.fromtimestamp(st.st_mtime).isoformat(timespec='seconds')
    return pg


# ---------------------------------------------------------------- SQLite（WAL + FTS5）

SCHEMA = """
CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT);
CREATE TABLE IF NOT EXISTS posts(
  id INTEGER PRIMARY KEY,
  path TEXT UNIQUE NOT NULL,
  url TEXT NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  categories TEXT NOT NULL DEFAULT '',
  tags TEXT NOT NULL DEFAULT '',
  words TEXT NOT NULL DEFAULT '',
  mtime TEXT NOT NULL DEFAULT ''
);
CREATE VIRTUAL TABLE IF NOT EXISTS posts_fts USING fts5(
  words, content='posts', content_rowid='id', tokenize='unicode61'
);
CREATE TRIGGER IF NOT EXISTS posts_ai AFTER INSERT ON posts BEGIN
  INSERT INTO posts_fts(rowid, words) VALUES (new.id, new.words);
END;
CREATE TRIGGER IF NOT EXISTS posts_ad AFTER DELETE ON posts BEGIN
  INSERT INTO posts_fts(posts_fts, rowid, words) VALUES ('delete', old.id, old.words);
END;
CREATE TRIGGER IF NOT EXISTS posts_au AFTER UPDATE ON posts BEGIN
  INSERT INTO posts_fts(posts_fts, rowid, words) VALUES ('delete', old.id, old.words);
  INSERT INTO posts_fts(rowid, words) VALUES (new.id, new.words);
END;
CREATE TABLE IF NOT EXISTS sections(
  post_id INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  ord INTEGER NOT NULL,
  anchor TEXT NOT NULL DEFAULT '',
  heading TEXT NOT NULL DEFAULT '',
  text TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_sections_post ON sections(post_id, ord);
CREATE TABLE IF NOT EXISTS visit(
  day TEXT NOT NULL, url TEXT NOT NULL, count INTEGER NOT NULL,
  PRIMARY KEY(day, url)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS visit_uv(
  day TEXT NOT NULL, vid TEXT NOT NULL,
  PRIMARY KEY(day, vid)
) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS visit_ref(
  day TEXT NOT NULL, host TEXT NOT NULL, count INTEGER NOT NULL,
  PRIMARY KEY(day, host)
) WITHOUT ROWID;
"""


def connect(db=None):
    conn = sqlite3.connect(db or DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute('PRAGMA journal_mode=WAL')
    conn.execute('PRAGMA synchronous=NORMAL')
    conn.execute('PRAGMA foreign_keys=ON')
    conn.execute('PRAGMA busy_timeout=8000')
    conn.executescript(SCHEMA)
    return conn


def get_meta(conn, key):
    row = conn.execute('SELECT v FROM meta WHERE k=?', (key,)).fetchone()
    return row[0] if row else ''


def set_meta(conn, key, value):
    conn.execute('INSERT INTO meta(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v', (key, value))


def _index_one(conn, rel, pg):
    """单事务内替换一篇（DELETE+INSERT，触发器同步 FTS；sections 随 FK 级联）。"""
    conn.execute('DELETE FROM sections WHERE post_id IN (SELECT id FROM posts WHERE path=?)', (rel,))
    conn.execute('DELETE FROM posts WHERE path=?', (rel,))
    words = build_words(pg['title'], pg['categories'], pg['tags'], [s[2] for s in pg['sections']])
    cur = conn.execute(
        'INSERT INTO posts(path,url,title,categories,tags,words,mtime) VALUES(?,?,?,?,?,?,?)',
        (rel, pg['url'], pg['title'], pg['categories'], pg['tags'], words, pg.get('mtime', '')),
    )
    pid = cur.lastrowid
    for i, (anchor, heading, text) in enumerate(pg['sections']):
        conn.execute(
            'INSERT INTO sections(post_id,ord,anchor,heading,text) VALUES(?,?,?,?,?)',
            (pid, i, anchor, heading, text),
        )


def _remove_one(conn, rel):
    conn.execute('DELETE FROM sections WHERE post_id IN (SELECT id FROM posts WHERE path=?)', (rel,))
    cur = conn.execute('DELETE FROM posts WHERE path=?', (rel,))
    return cur.rowcount > 0


def full_rebuild(root, db=None, release=''):
    pages = []
    for dp, dns, fns in os.walk(root):
        dns.sort()
        for fn in sorted(fns):
            if not fn.endswith('.html'):
                continue
            abspath = os.path.join(dp, fn)
            pg = parse_page(abspath)
            if pg and pg['url']:
                pg['path'] = os.path.relpath(abspath, root).replace(os.sep, '/')
                pages.append(pg)
    conn = connect(db)
    try:
        with conn:
            conn.execute('DELETE FROM sections')
            conn.execute('DELETE FROM posts')
            for pg in pages:
                _index_one(conn, pg['path'], pg)
            if release:
                set_meta(conn, 'last_release', release)
            set_meta(conn, 'last_full', datetime.now().isoformat(timespec='seconds'))
    finally:
        conn.close()
    return {'mode': 'full', 'indexed': len(pages)}


def _digests(root):
    """{相对路径: (size, md5)}，只看 html——增量差集的依据。"""
    out = {}
    for dp, dns, fns in os.walk(root):
        dns.sort()
        for fn in sorted(fns):
            if not fn.endswith('.html'):
                continue
            p = os.path.join(dp, fn)
            with open(p, 'rb') as f:
                data = f.read()
            out[os.path.relpath(p, root).replace(os.sep, '/')] = (len(data), hashlib.md5(data).hexdigest())
    return out


def incremental(prev_dir, cur_dir, db=None, release=''):
    """按两版 release 的文件差集只重解析变更页（等价 git diff，且覆盖 layouts/config 变更）。"""
    conn = connect(db)
    try:
        with conn:
            n = conn.execute('SELECT COUNT(*) FROM posts').fetchone()[0]
    finally:
        conn.close()
    if n == 0:   # DB 为空（首装/损坏）→ 自动退全量
        return full_rebuild(cur_dir, db, release)

    prev_d, cur_d = _digests(prev_dir), _digests(cur_dir)
    changed = sorted(r for r in cur_d if r not in prev_d or prev_d[r] != cur_d[r])
    deleted = sorted(r for r in prev_d if r not in cur_d)
    n_changed = n_deleted = n_indexed = 0
    conn = connect(db)
    try:
        with conn:
            for rel in deleted:
                if _remove_one(conn, rel):
                    n_deleted += 1
            for rel in changed:
                n_changed += 1
                abspath = os.path.join(cur_dir, rel.replace('/', os.sep))
                pg = parse_page(abspath) if os.path.isfile(abspath) else None
                if pg and pg['url']:
                    _index_one(conn, rel, pg)
                    n_indexed += 1
                elif _remove_one(conn, rel):
                    n_deleted += 1   # 该路径不再是文章页 → 从索引移除
            if release:
                set_meta(conn, 'last_release', release)
    finally:
        conn.close()
    return {'mode': 'incremental', 'changed': n_changed, 'indexed': n_indexed, 'deleted': n_deleted}


# ---------------------------------------------------------------- CLI

def main(argv=None):
    ap = argparse.ArgumentParser(description='阶段 3 检索索引（全量/增量，plan 3.2）')
    ap.add_argument('--full', action='store_true', help='全量重建（默认索引 current，可用 --root 覆盖）')
    ap.add_argument('--prev', default='', help='上一版 release 目录名（增量起点）')
    ap.add_argument('--cur', default='', help='这一版 release 目录名（增量目标）')
    ap.add_argument('--root', default='', help='覆盖索引根目录（仅 --full）')
    ap.add_argument('--db', default=DB_PATH, help='SQLite 文件路径')
    a = ap.parse_args(argv)
    if a.full:
        root = a.root or os.path.realpath(CURRENT_DIR)
        if not os.path.isdir(root):
            sys.exit(f'索引根不存在：{root}')
        out = full_rebuild(root, a.db)
    elif a.cur:
        cur_dir = os.path.join(RELEASES_DIR, a.cur)
        if not os.path.isdir(cur_dir):
            sys.exit(f'cur release 不存在：{cur_dir}')
        prev_dir = os.path.join(RELEASES_DIR, a.prev) if a.prev else None
        if prev_dir and os.path.isdir(prev_dir):
            out = incremental(prev_dir, cur_dir, a.db, release=a.cur)
        else:
            out = full_rebuild(cur_dir, a.db, release=a.cur)
    else:
        ap.error('需要 --full，或 --cur <release名>（可配 --prev <release名>）')
    print(json.dumps(out, ensure_ascii=False))


if __name__ == '__main__':
    main()
