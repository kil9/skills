#!/usr/bin/env python3
"""web-show 문서 서버.

등록한 파일을 /<slug>/ 로 서빙한다. md 는 브라우저 쪽에서 GFM·코드 하이라이트·mermaid 로
렌더링하고 mtime 폴링으로 새로고침 없이 갱신한다. 그 밖의 파일(html·이미지·pdf …)은 원본
그대로 준다. 등록한 파일의 디렉터리가 그 slug 의 루트라 상대 경로 자산(이미지·css)도 열린다.

  python3 server.py --port 18080 --state-dir DIR FILE [FILE ...]

등록 추가는 같은 머신에서만: POST /__register  (body = 절대경로 한 줄)
"""
import argparse
import html
import json
import mimetypes
import os
import re
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlsplit, parse_qs

MD_EXT = {".md", ".markdown", ".mdx"}
LOCK = threading.Lock()
REGISTRY = {}  # slug -> {"root": dir, "entry": filename}

PAGE = """<!doctype html>
<html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/github-markdown-css/5.5.1/github-markdown.min.css">
<link rel="stylesheet" media="(prefers-color-scheme: light)" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css">
<link rel="stylesheet" media="(prefers-color-scheme: dark)" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css">
<style>
  body {{ margin: 0; background: #fff; }}
  @media (prefers-color-scheme: dark) {{ body {{ background: #0d1117; }} }}
  .markdown-body {{ box-sizing: border-box; max-width: 980px; margin: 0 auto; padding: 32px 16px 64px; }}
  #ws-status {{ position: fixed; top: 6px; right: 10px; font: 12px system-ui; opacity: .5; }}
</style></head>
<body><div id="ws-status"></div><article id="doc" class="markdown-body">불러오는 중…</article>
<script src="https://cdn.jsdelivr.net/npm/marked@12.0.2/marked.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js"></script>
<script>
const SRC = {src};
const dark = matchMedia('(prefers-color-scheme: dark)').matches;
mermaid.initialize({{ startOnLoad: false, theme: dark ? 'dark' : 'default' }});
let last = null, n = 0;
async function render() {{
  const r = await fetch(SRC + '?raw=1', {{ cache: 'no-store' }});
  const text = await r.text();
  const y = scrollY;
  const doc = document.getElementById('doc');
  doc.innerHTML = marked.parse(text, {{ gfm: true }});
  doc.querySelectorAll('pre code').forEach(el => {{
    if (el.classList.contains('language-mermaid')) {{
      const d = document.createElement('div');
      d.className = 'mermaid'; d.textContent = el.textContent;
      el.parentElement.replaceWith(d);
    }} else hljs.highlightElement(el);
  }});
  try {{ await mermaid.run({{ querySelector: '.mermaid' }}); }} catch (e) {{ console.error(e); }}
  scrollTo(0, y);
  const h = doc.querySelector('h1');
  if (h) document.title = h.textContent;
}}
async function poll() {{
  try {{
    const r = await fetch(SRC + '?mtime=1', {{ cache: 'no-store' }});
    const m = await r.text();
    if (m !== last) {{ last = m; await render();
      document.getElementById('ws-status').textContent = n++ ? '갱신 ' + new Date().toLocaleTimeString() : ''; }}
  }} catch (e) {{ document.getElementById('ws-status').textContent = '서버 연결 끊김'; }}
  setTimeout(poll, 1000);
}}
poll();
</script></body></html>
"""


def slugify(name):
    s = re.sub(r"[^0-9A-Za-z가-힣._-]+", "-", os.path.splitext(name)[0]).strip("-") or "doc"
    return s[:60]


def register(path):
    path = os.path.realpath(path)
    if not os.path.isfile(path):
        raise FileNotFoundError(path)
    root, entry = os.path.split(path)
    with LOCK:
        for slug, e in REGISTRY.items():
            if e["root"] == root and e["entry"] == entry:
                return slug
        base = slug = slugify(entry)
        i = 2
        while slug in REGISTRY:
            slug = f"{base}-{i}"
            i += 1
        REGISTRY[slug] = {"root": root, "entry": entry}
        return slug


class Handler(BaseHTTPRequestHandler):
    server_version = "web-show"

    def log_message(self, fmt, *args):
        pass

    def send(self, code, body, ctype="text/plain; charset=utf-8"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/__register" or self.client_address[0] not in ("127.0.0.1", "::1"):
            return self.send(403, "forbidden\n")
        length = int(self.headers.get("Content-Length") or 0)
        path = self.rfile.read(length).decode().strip()
        try:
            slug = register(path)
        except FileNotFoundError:
            return self.send(404, f"not a file: {path}\n")
        self.send(200, slug + "\n")

    def do_GET(self):
        url = urlsplit(self.path)
        q = parse_qs(url.query)
        parts = [unquote(p) for p in url.path.split("/") if p]
        if not parts:
            return self.index()
        with LOCK:
            e = REGISTRY.get(parts[0])
        if not e:
            return self.send(404, "등록되지 않은 문서\n")
        if len(parts) == 1 and not url.path.endswith("/"):
            self.send_response(301)
            self.send_header("Location", f"/{parts[0]}/")
            self.end_headers()
            return
        rel = "/".join(parts[1:]) or e["entry"]
        target = os.path.realpath(os.path.join(e["root"], rel))
        if not (target == e["root"] or target.startswith(e["root"] + os.sep)):
            return self.send(403, "forbidden\n")
        if not os.path.isfile(target):
            return self.send(404, "없는 파일\n")
        if "mtime" in q:
            return self.send(200, str(os.stat(target).st_mtime_ns))
        is_md = os.path.splitext(target)[1].lower() in MD_EXT
        if is_md and "raw" not in q:
            src = "/" + parts[0] + "/" + "/".join(parts[1:]) if len(parts) > 1 else f"/{parts[0]}/{e['entry']}"
            page = PAGE.format(title=html.escape(os.path.basename(target)), src=json.dumps(src))
            return self.send(200, page, "text/html; charset=utf-8")
        with open(target, "rb") as f:
            data = f.read()
        ctype = "text/markdown; charset=utf-8" if is_md else (mimetypes.guess_type(target)[0] or "application/octet-stream")
        if ctype.startswith("text/") and "charset" not in ctype:
            ctype += "; charset=utf-8"
        self.send(200, data, ctype)

    def index(self):
        with LOCK:
            items = sorted(REGISTRY.items())
        rows = "".join(
            f'<li><a href="/{html.escape(s)}/">{html.escape(e["entry"])}</a> '
            f'<small>{html.escape(e["root"])}</small></li>' for s, e in items)
        self.send(200, f'<!doctype html><meta charset="utf-8"><meta name="viewport" '
                       f'content="width=device-width, initial-scale=1"><title>web-show</title>'
                       f'<body style="font:15px system-ui;padding:16px"><ul>{rows}</ul>',
                  "text/html; charset=utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--bind", default="0.0.0.0")
    ap.add_argument("files", nargs="*")
    a = ap.parse_args()
    slugs = [register(f) for f in a.files]
    srv = ThreadingHTTPServer((a.bind, a.port), Handler)
    print("READY " + " ".join(slugs), flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    sys.exit(main())
