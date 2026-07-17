#!/usr/bin/env python3
"""일회용/상시 HTTP paste 업로드 서버.

브라우저에서 Ctrl+V 또는 drag-and-drop 으로 이미지를 업로드하면
로컬 디렉토리에 저장한 뒤 절대 경로를 stdout 에 출력한다.
기본(일회용)은 첫 성공 업로드 혹은 타임아웃 시 스스로 종료하고,
--persist 는 종료하지 않고 업로드를 계속 받는다.
업로드 페이지는 저장된 원격 경로를 브라우저(로컬) 클립보드에 복사해 준다.

출력 규약 (skill 이 파싱):
  stderr: LISTEN:http://<host>:<port>/<token>/
  stdout: SAVED:<abs_path>       (성공. 일회용은 1회 후 exit 0, persist 는 업로드마다 1줄)
  stdout: TIMEOUT                 (일회용 타임아웃, exit 2)
"""
from __future__ import annotations

import argparse
import json
import os
import secrets
import socket
import sys
import tempfile
import threading
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path


DEFAULT_PORT = 13000
PORT_PROBE_MAX = 10
DEFAULT_TIMEOUT = 600
MAX_UPLOAD_BYTES = 20 * 1024 * 1024  # 20 MB

EXT_BY_MIME = {
    "image/png": ".png",
    "image/jpeg": ".jpg",
    "image/gif": ".gif",
    "image/webp": ".webp",
    "image/bmp": ".bmp",
    "image/heic": ".heic",
    "image/heif": ".heif",
}


PASTE_HTML = """<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="utf-8">
<title>paste-image</title>
<style>
  body { font-family: -apple-system, "SF Pro Text", system-ui, sans-serif; background: #111;
         color: #eee; display: flex; flex-direction: column; align-items: center;
         justify-content: center; min-height: 100vh; margin: 0; gap: 1.25rem; padding: 1rem; }
  #drop { border: 2px dashed #555; border-radius: 12px; padding: 2.5rem 4rem;
          text-align: center; transition: border-color .15s, background .15s; max-width: 80vw; }
  #drop.hover { border-color: #4ea1ff; background: #122036; }
  #preview { max-width: 70vw; max-height: 45vh; border-radius: 8px;
             box-shadow: 0 4px 20px rgba(0,0,0,.4); }
  #status { min-height: 1.5em; font-size: 1.05rem; text-align: center; }
  #pathbox { display: flex; align-items: center; gap: .6rem; max-width: 85vw; }
  #pathText { background: #1c1c1c; border: 1px solid #444; border-radius: 6px;
              padding: .45rem .7rem; font-size: .95rem; user-select: all;
              overflow-wrap: anywhere; }
  button { background: #333; color: #eee; border: 1px solid #555; padding: .5rem 1rem;
           border-radius: 6px; cursor: pointer; font: inherit; }
  button:hover { background: #444; }
  .ok { color: #6ed96e; }
  .err { color: #ff7777; }
</style>
</head>
<body>
  <div id="drop">
    <p>Ctrl+V 로 이미지를 붙여넣거나 이 영역에 파일을 드롭하세요.</p>
  </div>
  <img id="preview" hidden alt="preview">
  <div id="status"></div>
  <div id="pathbox" hidden>
    <code id="pathText"></code>
    <button id="copyBtn">경로 복사</button>
  </div>
  <button id="cancel" hidden>취소</button>
<script>
  const UPLOAD_URL = "__UPLOAD_URL__";
  const PERSIST = "__PERSIST__" === "1";
  const drop = document.getElementById('drop');
  const preview = document.getElementById('preview');
  const statusEl = document.getElementById('status');
  const cancelBtn = document.getElementById('cancel');
  const pathbox = document.getElementById('pathbox');
  const pathText = document.getElementById('pathText');
  const copyBtn = document.getElementById('copyBtn');
  let controller = null;
  let busy = false;

  function setStatus(msg, cls) {
    statusEl.textContent = msg || '';
    statusEl.className = cls || '';
  }

  // http(비보안 컨텍스트)에선 navigator.clipboard 가 없어 execCommand 로 폴백한다.
  async function copyText(t) {
    if (!t) return false;
    if (navigator.clipboard && window.isSecureContext) {
      try { await navigator.clipboard.writeText(t); return true; } catch (e) {}
    }
    const ta = document.createElement('textarea');
    ta.value = t;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    let ok = false;
    try { ok = document.execCommand('copy'); } catch (e) {}
    ta.remove();
    return ok;
  }

  async function upload(blob, mime) {
    if (busy) return;
    busy = true;
    const url = URL.createObjectURL(blob);
    preview.src = url;
    preview.hidden = false;
    setStatus('전송 중…');
    cancelBtn.hidden = false;
    controller = new AbortController();
    try {
      const res = await fetch(UPLOAD_URL, {
        method: 'POST',
        headers: { 'Content-Type': mime || 'application/octet-stream' },
        body: blob,
        signal: controller.signal,
      });
      const text = await res.text();
      if (!res.ok) {
        setStatus('업로드 실패 (' + res.status + '): ' + text, 'err');
        cancelBtn.hidden = true;
        busy = false;
        return;
      }
      let savedPath = '';
      try { savedPath = JSON.parse(text).path || ''; } catch (err) {}
      if (savedPath) {
        pathText.textContent = savedPath;
        pathbox.hidden = false;
        const again = PERSIST ? ' 계속 붙여넣을 수 있습니다.' : ' 이 탭을 닫아도 됩니다.';
        const copied = await copyText(savedPath);
        setStatus(copied
          ? '업로드 완료 — 원격 경로를 클립보드에 복사했습니다. 챗창에 붙여넣으세요.' + again
          : '업로드 완료 — 아래 경로를 복사해 챗창에 붙여넣으세요.' + again, 'ok');
      } else {
        setStatus('업로드 완료 — 이 탭을 닫아도 됩니다.', 'ok');
      }
      cancelBtn.hidden = true;
      if (PERSIST) busy = false;
    } catch (e) {
      if (e.name === 'AbortError') {
        setStatus('취소됨. 다시 시도하세요.', '');
      } else {
        setStatus('네트워크 오류: ' + e.message, 'err');
      }
      cancelBtn.hidden = true;
      busy = false;
    }
  }

  cancelBtn.addEventListener('click', () => { if (controller) controller.abort(); });

  copyBtn.addEventListener('click', async () => {
    const ok = await copyText(pathText.textContent);
    setStatus(ok ? '경로 복사됨 — 챗창에 붙여넣으세요.'
                 : '복사 실패 — 경로를 드래그해 직접 복사하세요.', ok ? 'ok' : 'err');
  });

  document.addEventListener('paste', (e) => {
    const items = e.clipboardData && e.clipboardData.items;
    if (!items) return;
    for (const it of items) {
      if (it.kind === 'file' && it.type.startsWith('image/')) {
        const file = it.getAsFile();
        if (file) { upload(file, it.type); return; }
      }
    }
  });

  ['dragenter', 'dragover'].forEach(ev =>
    drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.add('hover'); }));
  ['dragleave'].forEach(ev =>
    drop.addEventListener(ev, () => drop.classList.remove('hover')));
  drop.addEventListener('drop', (e) => {
    e.preventDefault();
    drop.classList.remove('hover');
    const files = e.dataTransfer && e.dataTransfer.files;
    if (!files || !files.length) return;
    for (const f of files) {
      if (f.type.startsWith('image/')) { upload(f, f.type); return; }
    }
    setStatus('이미지 파일이 아닙니다.', 'err');
  });
</script>
</body>
</html>
"""


# Windows 에서는 SO_REUSEADDR 가 활성 리슨 소켓과의 동시 바인딩까지 허용해 좀비 서버와
# 충돌하므로 금지. POSIX 에서는 TIME_WAIT 재사용만 허용되고 활성 중복은 막히므로 안전하며,
# 켜지 않으면 재시작 직후 TIME_WAIT 탓에 포트가 드리프트해 북마크 URL 이 깨진다.
REUSE_ADDR = os.name == "posix"


def pick_port(start: int, bind_host: str = "0.0.0.0") -> int:
    """start 부터 최대 PORT_PROBE_MAX 개 포트를 순서대로 probe 하여 사용 가능 포트 반환."""
    last_err: OSError | None = None
    for offset in range(PORT_PROBE_MAX):
        port = start + offset
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                if REUSE_ADDR:
                    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                sock.bind((bind_host, port))
            return port
        except OSError as e:
            last_err = e
    raise RuntimeError(
        f"port {start}-{start + PORT_PROBE_MAX - 1} 모두 점유: {last_err}"
    )


def resolve_save_dir(primary: Path, fallback: Path) -> Path:
    """primary 를 우선 시도하고, 쓰기 불가 시 fallback 으로 폴백."""
    candidates = [primary]
    if fallback.resolve() != primary.resolve():
        candidates.append(fallback)
    for cand in candidates:
        try:
            cand.mkdir(parents=True, exist_ok=True)
            probe = cand / f".write-test-{secrets.token_hex(4)}"
            probe.write_text("")
            probe.unlink()
            if cand != primary:
                print(
                    f"WARN: {primary} 에 쓸 수 없어 {cand} 로 폴백합니다.",
                    file=sys.stderr,
                )
            return cand
        except OSError:
            continue
    raise RuntimeError(f"저장 가능한 디렉토리를 찾지 못함: {primary}, {fallback}")


def build_handler(token: str, save_dir: Path, on_success, persist: bool = False):
    token_prefix = f"/{token}/"
    upload_path = f"/{token}/upload"
    # 상대 URL을 사용해 Funnel base path prefix 유무에 무관하게 동작
    html_upload_url = "upload"
    persist_flag = "1" if persist else "0"

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format, *args):  # stderr 오염 방지
            return

        def _send(self, status: int, body: bytes, content_type: str):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def _send_json(self, status: int, payload: dict):
            self._send(
                status,
                json.dumps(payload).encode("utf-8"),
                "application/json; charset=utf-8",
            )

        def _path(self) -> str:
            return self.path.split("?", 1)[0]

        def do_GET(self):
            path = self._path()
            if path in (token_prefix, token_prefix.rstrip("/")):
                body = (PASTE_HTML
                        .replace("__UPLOAD_URL__", html_upload_url)
                        .replace("__PERSIST__", persist_flag)
                        .encode("utf-8"))
                self._send(200, body, "text/html; charset=utf-8")
                return
            self._send(404, b"not found", "text/plain; charset=utf-8")

        def do_POST(self):
            if self._path() != upload_path:
                self._send(404, b"not found", "text/plain; charset=utf-8")
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                self._send_json(400, {"ok": False, "error": "invalid Content-Length"})
                return
            if length <= 0:
                self._send_json(400, {"ok": False, "error": "empty body"})
                return
            if length > MAX_UPLOAD_BYTES:
                self._send_json(413, {"ok": False, "error": "payload too large"})
                return
            mime = (self.headers.get("Content-Type") or "").split(";", 1)[0].strip().lower()
            ext = EXT_BY_MIME.get(mime)
            if ext is None:
                self._send_json(
                    415,
                    {"ok": False, "error": f"unsupported media type: {mime or '<none>'}"},
                )
                return
            data = self.rfile.read(length)
            if len(data) != length:
                self._send_json(400, {"ok": False, "error": "truncated body"})
                return
            timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            filename = f"paste-{timestamp}-{secrets.token_hex(2)}{ext}"
            full_path = (save_dir / filename).resolve()
            full_path.write_bytes(data)
            self._send_json(200, {"ok": True, "path": str(full_path)})
            on_success(str(full_path))

    return Handler


class PasteServer:
    def __init__(self, port: int, save_dir: Path, hostname_hint: str,
                 listen_file: str | None = None, public_url_base: str | None = None,
                 bind_host: str = "0.0.0.0", persist: bool = False,
                 token: str | None = None):
        self.port = port
        self.save_dir = save_dir
        self.hostname_hint = hostname_hint
        self.bind_host = bind_host
        self.listen_file = listen_file
        self.public_url_base = public_url_base.rstrip("/") if public_url_base else None
        self.persist = persist
        self.token = token or secrets.token_urlsafe(8)
        self._server: HTTPServer | None = None
        self._saved_path: str | None = None
        self._success = threading.Event()

    def _on_success(self, path: str) -> None:
        self._saved_path = path
        if self.persist:
            print(f"SAVED:{path}", flush=True)
            return
        self._success.set()
        # shutdown() 은 serve_forever 루프를 다른 스레드에서 중단시키는 용도.
        # 현재 핸들러 스레드에서 직접 호출 시 데드락 가능성 → 데몬 스레드에 위임.
        threading.Thread(target=self._server.shutdown, daemon=True).start()

    def listen_url(self) -> str:
        if self.public_url_base:
            return f"{self.public_url_base}/{self.token}/"
        return f"http://{self.hostname_hint}:{self.port}/{self.token}/"

    def run(self, timeout: float) -> int:
        handler_cls = build_handler(self.token, self.save_dir, self._on_success,
                                    persist=self.persist)

        class ExclusiveHTTPServer(HTTPServer):
            # REUSE_ADDR 주석 참조 — Windows 만 배타 바인딩.
            allow_reuse_address = REUSE_ADDR

        self._server = ExclusiveHTTPServer((self.bind_host, self.port), handler_cls)
        listen_url = self.listen_url()
        print(f"LISTEN:{listen_url}", file=sys.stderr, flush=True)
        if self.listen_file:
            Path(self.listen_file).write_text(f"{listen_url}\n")

        if not self.persist:
            def trigger_timeout() -> None:
                if not self._success.wait(timeout):
                    threading.Thread(target=self._server.shutdown, daemon=True).start()

            threading.Thread(target=trigger_timeout, daemon=True).start()
        try:
            self._server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            self._server.server_close()

        if self.persist:
            return 0
        if self._success.is_set() and self._saved_path:
            print(f"SAVED:{self._saved_path}", flush=True)
            return 0
        print("TIMEOUT", flush=True)
        return 2


def parse_args(argv):
    parser = argparse.ArgumentParser(description="일회용 paste 이미지 업로드 서버")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT,
                        help=f"시작 포트 (기본 {DEFAULT_PORT}, 충돌 시 +1 로 최대 {PORT_PROBE_MAX} 회 probe)")
    parser.add_argument("--save-dir", default=None,
                        help="저장 디렉토리. 지정 시 우선 사용, 미지정 시 OS 임시 디렉토리 사용. 둘 다 쓰기 불가면 <cwd>/tmp 로 폴백")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT,
                        help=f"업로드 대기 상한(초). 기본 {DEFAULT_TIMEOUT}. --persist 에선 무시")
    parser.add_argument("--persist", action="store_true",
                        help="첫 업로드 후에도 종료하지 않고 상주. 업로드마다 SAVED:<path> 를 stdout 에 출력")
    parser.add_argument("--token-file", default=None,
                        help="URL 토큰 영속화 파일. 있으면 재사용, 없으면 생성해 기록 (북마크용 URL 고정)")
    parser.add_argument("--host-hint", default=None,
                        help="LISTEN URL 의 호스트명. 기본: $PASTE_IMAGE_HOST_DOMAIN 설정 시 "
                             "$(hostname).$PASTE_IMAGE_HOST_DOMAIN, 미설정 시 localhost")
    parser.add_argument("--listen-file", default=None,
                        help="서버 시작 시 LISTEN URL 을 이 파일에 기록 (배경 실행 시 동기화용)")
    parser.add_argument("--public-url-base", default=None,
                        help="Tailscale Funnel 등 역방향 프록시 사용 시 공개 URL 베이스 "
                             "(예: https://host.ts.net/paste). 설정 시 --host-hint 무시. "
                             "LISTEN URL 표시에만 쓰이며 서버 라우트에는 적용되지 않으므로, "
                             "프록시가 경로 prefix 를 제거하고 전달해야 한다 "
                             "(tailscale serve/funnel --set-path 기본 동작). "
                             "업로드 페이지는 상대 URL 을 쓰므로 prefix 유무와 무관하게 동작.")
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)

    primary = Path(args.save_dir).expanduser().resolve() if args.save_dir else Path(tempfile.gettempdir())
    fallback = Path.cwd() / "tmp"
    save_dir = resolve_save_dir(primary, fallback)

    _host_domain = os.environ.get("PASTE_IMAGE_HOST_DOMAIN")
    host_hint = args.host_hint or (
        f"{socket.gethostname()}.{_host_domain}" if _host_domain else "localhost")
    # 접속 호스트가 localhost 계열이면 루프백에만 바인드 — 외부 인터페이스 불필요 노출 방지
    bind_host = "127.0.0.1" if host_hint in ("localhost", "127.0.0.1") else "0.0.0.0"

    port = pick_port(args.port, bind_host)
    if port != args.port:
        print(f"WARN: port {args.port} 점유 중 → {port} 사용", file=sys.stderr)

    token = None
    if args.token_file:
        token_path = Path(args.token_file).expanduser()
        if token_path.is_file() and token_path.read_text().strip():
            token = token_path.read_text().strip()
        else:
            token = secrets.token_urlsafe(16)
            token_path.parent.mkdir(parents=True, exist_ok=True)
            token_path.write_text(f"{token}\n")

    server = PasteServer(port=port, save_dir=save_dir, hostname_hint=host_hint,
                         listen_file=args.listen_file, public_url_base=args.public_url_base,
                         bind_host=bind_host, persist=args.persist, token=token)
    return server.run(timeout=args.timeout)


if __name__ == "__main__":
    sys.exit(main())
