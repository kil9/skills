#!/usr/bin/env python3
"""덱 검사. 빌드된 out/d*.html 을 읽어 기계로 잴 수 있는 규칙을 본다. 실패가 하나라도 있으면 exit 1.

    python3 check.py <프로젝트>             # 전부(정적 검사)
    python3 check.py <프로젝트> 3 4         # 덱 3·4 만(총 장수 검사는 건너뜀)
    python3 check.py <프로젝트> --render    # headless chromium 으로 열어 넘침·제목 겹침·SVG 글자 잘림까지

course.py 에서 덮어쓸 수 있는 값: TOTAL = (최소, 최대) 총 장수, BANNED·WARN 에 더할 낱말 목록(EXTRA_BANNED·EXTRA_WARN).
WARN 은 실패로 치지 않고 보여만 준다(문맥에 따라 맞는 말일 수 있다).
"""
import glob
import importlib.util
import json
import os
import re
import subprocess
import sys
from pathlib import Path

MAX_LINES = 4          # 슬라이드당 문장 줄(say 의 p + 그 밖의 맨 p)
MAX_LINE_CHARS = 110   # 한 줄 글자 수(태그 뺀 값)
MAX_ASIDE_LINES = 3    # 곁들임 패널 줄. 문장 줄과 따로 센다
BANNED = ["—", "TODO", "TBD", "lorem"]
# 실무에서 안 쓰는 풀어 쓴 말, 이전 판을 전제한 말, 무형의 것을 장소·사물에 빗댄 말
WARN = {"위쪽 한계": "상한", "아래쪽 한계": "하한", "이전 판": "처음 쓰는 문서처럼", "바뀐 것": "처음 쓰는 문서처럼",
        "자리": "줄·단계·시점 등 관계로", "손잡이": "명령·플래그 등 이름으로"}


def text(s):
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", s)).strip()


def check_file(f: Path, lecture: bool, banned, warn, fails, warns):
    s = f.read_text(encoding="utf-8")
    secs = re.findall(r'<section class="s ([^"]*)"[^>]*data-n="(\d+)">(.*?)</section>', s, re.S)
    for kind, n, body in secs:
        where = f"{f.name}#{n}"
        title = text(re.search(r"<h[12]>(.*?)</h[12]>", body, re.S).group(1))
        if kind != "cover" and "<table" not in body and "<svg" not in body:
            fails.append(f"{where} 표·그림 없음: {title}")
        noviz = re.sub(r"<table.*?</table>|<svg.*?</svg>|<pre.*?</pre>", "", body, flags=re.S)
        for o in re.findall(r'<div class="aside">(.*?)</div>', noviz, re.S):
            ps = [text(p) for p in re.findall(r"<p>(.*?)</p>", o, re.S)]
            if len(ps) > MAX_ASIDE_LINES:
                fails.append(f"{where} 곁들임 패널 {len(ps)}줄 > {MAX_ASIDE_LINES}: {title}")
            for p in ps:
                if len(p) > MAX_LINE_CHARS:
                    fails.append(f"{where} 한 줄 {len(p)}자 > {MAX_LINE_CHARS}: {p[:40]}…")
        noviz = re.sub(r'<div class="aside">.*?</div>', "", noviz, flags=re.S)
        ps = [text(p) for p in re.findall(r"<p(?! class=\"src\")[^>]*>(.*?)</p>", noviz, re.S)]
        if len(ps) > MAX_LINES:
            fails.append(f"{where} 문장 {len(ps)}줄 > {MAX_LINES}: {title}")
        for p in ps:
            if len(p) > MAX_LINE_CHARS:
                fails.append(f"{where} 한 줄 {len(p)}자 > {MAX_LINE_CHARS}: {p[:40]}…")
            if p.count(" · ") >= 2:
                warns.append(f"{where} 문장에 가운뎃점 나열(문장은 쉼표, 가운뎃점은 표·라벨): {p[:40]}…")
        t = text(body)
        for b in banned:
            if b in t:
                fails.append(f"{where} 금지 문자 {b!r}: {title}")
        for w, alt in warn.items():
            if w in t:
                warns.append(f"{where} {w!r} → {alt}: {title}")
        if re.search(r"\d\s*~\s*\d", t):
            fails.append(f"{where} 범위에 ~ (- 를 쓴다): {title}")
        if "<svg" in body and "viewBox" not in body:
            fails.append(f"{where} svg viewBox 없음")
    kinds = [k.split()[0] if k else "" for k, _, _ in secs]
    if lecture and f.name != "d00.html":
        for need in ("summary", "quiz", "answer"):
            if need not in kinds:
                fails.append(f"{f.name} {need} 슬라이드 없음")
    if re.search(r'<(?:script|link|img)[^>]+(?:src|href)="https?://', s):
        fails.append(f"{f.name} 외부 리소스")
    return len(secs)


def headless():
    c = sorted(glob.glob(os.path.expanduser("~/.cache/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-*/chrome-headless-shell")))
    if c:
        return c[-1]
    for b in ("chromium", "chromium-browser", "google-chrome"):
        for d in os.environ.get("PATH", "").split(":"):
            if os.access(os.path.join(d, b), os.X_OK):
                return os.path.join(d, b)
    return None


def render_check(f: Path, fails):
    """페이지를 ?check 로 열어 deck.py 의 JS 가 잰 넘침·겹침·잘림을 읽는다."""
    b = headless()
    if not b:
        fails.append("--render: headless chromium 없음(`python3 -m playwright install chromium-headless-shell`)")
        return
    r = subprocess.run([b, "--headless", "--disable-gpu", "--window-size=1300,780", "--virtual-time-budget=4000",
                        "--dump-dom", f"file://{f}?check"], capture_output=True, text=True, timeout=120)
    m = re.search(r'<pre id="__check">(.*?)</pre>', r.stdout, re.S)
    if not m:
        fails.append(f"{f.name} --render: 결과 없음(JS 오류?)")
        return
    for n, msg in json.loads(m.group(1).replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")):
        fails.append(f"{f.name}#{n} {msg}")


def main(argv):
    if not argv:
        sys.exit(__doc__)
    root = Path(argv[0]).resolve()
    render = "--render" in argv
    nos = [a for a in argv[1:] if a != "--render"]
    spec = importlib.util.spec_from_file_location("course", root / "course.py")
    c = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(c)
    lecture = getattr(c, "LECTURE", True)
    banned = BANNED + list(getattr(c, "EXTRA_BANNED", []))
    warn = {**WARN, **dict(getattr(c, "EXTRA_WARN", {}))}
    out = root / "out"
    files = [out / f"d{int(a):02d}.html" for a in nos] if nos else sorted(out.glob("d*.html"))
    fails, warns, counts = [], [], {}
    for f in files:
        if not f.exists():
            fails.append(f"{f.name} 없음 (build.py 먼저)")
            continue
        counts[f.name] = check_file(f, lecture, banned, warn, fails, warns)
        if render:
            render_check(f, fails)
    for k, v in counts.items():
        print(f"{k}: {v}장")
    if not nos and hasattr(c, "TOTAL"):
        total, (lo, hi) = sum(counts.values()), c.TOTAL
        print(f"총 {total}장")
        if not lo <= total <= hi:
            fails.append(f"총 장수 {total} ({lo}-{hi})")
    for x in warns:
        print("WARN", x)
    for x in fails:
        print("FAIL", x)
    print("PASS" if not fails else f"FAIL {len(fails)}")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main(sys.argv[1:])
