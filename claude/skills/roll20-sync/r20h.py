# /// script
# requires-python = ">=3.10"
# dependencies = ["markdown", "pyyaml"]
# ///
"""Roll20 원본 디렉터리 <-> 페이지 JS 페이로드.

  uv run r20h.py build  DIR [KEY ...]    # 새 그림을 공개하고 실행할 JS 를 DIR/.r20h-payload.js 에 쓴다
  uv run r20h.py record DIR RESULT.json  # 실행 결과의 id 를 DIR/roll20.json 에 기록

DIR 구조는 SKILL.md 의 '원본 디렉터리' 절을 본다.
"""
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import time
import urllib.request

import markdown
import yaml

HERE = pathlib.Path(__file__).resolve().parent
GM_SPLIT = "<!-- gm -->"
# 폴더(= roll20.json 의 id 맵 키) → (JS kind, 본문 blob 이름)
KINDS = {
    "handouts": ("handout", "notes"),
    "characters": ("character", "bio"),
}


def players(v):
    if v is None or v in ("gm", "all"):
        return v or "gm"
    if isinstance(v, str):
        v = v.split(",")
    return [str(x).strip() for x in v if str(x).strip()]


class Assets:
    """원본이 가리키는 저장소 안 그림 파일을 공개 그림 저장소에 넣고 주소를 돌려준다.

    roll20.json 의 "assets": {"dir": 그림 저장소 로컬 클론, "base_url": 그 저장소가 공개되는 주소}.
    파일 이름은 내용 해시라 같은 그림은 같은 주소, 그림을 고치면 새 주소가 된다.
    """

    def __init__(self, cfg: dict):
        a = cfg.get("assets")
        self.dir = pathlib.Path(a["dir"]).expanduser() if a else None
        self.base = a["base_url"].rstrip("/") + "/" if a else None
        self.new: list[tuple[pathlib.Path, str]] = []

    def url(self, src: pathlib.Path) -> str:
        if not self.dir:
            sys.exit(f"{src}: 로컬 그림을 쓰려면 roll20.json 에 assets 설정이 필요하다")
        if not src.is_file():
            sys.exit(f"그림 파일 없음: {src}")
        data = src.read_bytes()
        name = f"i/{hashlib.sha256(data).hexdigest()[:20]}{src.suffix.lower()}"
        url = self.base + name
        dst = self.dir / name
        if not dst.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(data)
            self.new.append((dst, url))
        return url

    def resolve(self, ref: str, base: pathlib.Path) -> str:
        return ref if re.match(r"^(https?:|data:)", ref) else self.url((base / ref).resolve())

    def publish(self) -> None:
        """새 그림을 커밋·push 하고 공개 주소가 200 을 줄 때까지 기다린다."""
        if not self.new:
            return
        git = ["git", "-C", str(self.dir)]
        subprocess.run([*git, "add", *[str(p.relative_to(self.dir)) for p, _ in self.new]], check=True)
        subprocess.run([*git, "commit", "-q", "-m", f"그림 {len(self.new)}장 추가"], check=True)
        subprocess.run([*git, "push", "-q"], check=True)
        pending = [u for _, u in self.new]
        for _ in range(60):  # GitHub Pages 배포는 보통 1분 안팎
            pending = [u for u in pending if not ok(u)]
            if not pending:
                print(f"그림 {len(self.new)}장 공개 확인")
                return
            time.sleep(5)
        sys.exit(f"그림 주소가 아직 안 열린다: {', '.join(pending)}")


def ok(url: str) -> bool:
    try:
        with urllib.request.urlopen(urllib.request.Request(url, method="HEAD"), timeout=10) as r:
            return r.status == 200
    except Exception:
        return False


def md(s: str) -> str:
    s = s.strip()
    return markdown.markdown(s, extensions=["tables", "sane_lists"]) if s else ""


def parse(path: pathlib.Path, body_field: str, assets: Assets) -> dict:
    text = path.read_text(encoding="utf-8")
    meta = {}
    if text.startswith("---\n"):
        head, _, text = text[4:].partition("\n---\n")
        meta = yaml.safe_load(head) or {}
    if "name" not in meta:
        sys.exit(f"{path}: frontmatter 에 name 이 없다")
    body, _, gm = text.partition(GM_SPLIT)
    here = path.parent
    imgs = lambda html: re.sub(r'(<img[^>]*\ssrc=")([^"]+)"', lambda m: m[1] + assets.resolve(m[2], here) + '"', html)
    item = {
        "key": path.stem,
        "name": str(meta["name"]),
        body_field: imgs(md(body)),
        "gmnotes": imgs(md(gm)),
        "visibleTo": players(meta.get("visible_to")),
    }
    if "controlled_by" in meta:
        item["controlledBy"] = players(meta["controlled_by"])
    if meta.get("avatar"):
        item["avatar"] = assets.resolve(str(meta["avatar"]), here)
    if "archived" in meta:
        item["archived"] = meta["archived"]
    if meta.get("sheet"):
        item["sheet"] = meta["sheet"]
    return item


def load_cfg(d: pathlib.Path) -> dict:
    p = d / "roll20.json"
    if not p.exists():
        sys.exit(f"{p} 가 없다 — {{\"campaign_id\": <게임 ID>}} 로 만든다")
    return json.loads(p.read_text(encoding="utf-8"))


def build(d: pathlib.Path, keys: list[str]) -> None:
    cfg = load_cfg(d)
    assets = Assets(cfg)
    js = (HERE / "r20h.js").read_text(encoding="utf-8")
    calls, summary, seen = [], [], set()
    for folder, (kind, body_field) in KINDS.items():
        ids = cfg.get(folder, {})
        items = []
        for p in sorted((d / folder).glob("*.md")):
            if keys and p.stem not in keys:
                continue
            seen.add(p.stem)
            it = parse(p, body_field, assets)
            if it["key"] in ids:
                it["id"] = ids[it["key"]]
            items.append(it)
            summary.append(f"{folder}/{it['key']}" + ("" if "id" in it else "(신규)"))
        if items:
            payload = json.dumps(items, ensure_ascii=False)
            calls.append(f"{json.dumps(folder)}: await R20H.upsert({json.dumps(cfg['campaign_id'])}, '{kind}', {payload})")
    if missing := set(keys) - seen:
        sys.exit(f"원본 파일 없음: {', '.join(sorted(missing))}")
    if not calls:
        sys.exit("반영할 원본이 없다")
    assets.publish()  # 롤20이 그림을 받으려면 페이로드 실행 전에 공개돼 있어야 한다
    out = d / ".r20h-payload.js"
    out.write_text(f"{js}\n({{{', '.join(calls)}}});\n", encoding="utf-8")
    print(f"{out} ({len(summary)}개: {', '.join(summary)})")


def record(d: pathlib.Path, result_path: str) -> None:
    cfg = load_cfg(d)
    results = json.loads(pathlib.Path(result_path).read_text(encoding="utf-8"))
    ok = errs = 0
    for folder, rs in results.items():
        ids = cfg.setdefault(folder, {})
        for r in rs:
            if r.get("id") and r.get("action") in ("created", "updated", "error"):
                ids[r["key"]] = r["id"]  # 시트 값 불일치 같은 오류여도 만들어진 id 는 남긴다
            if r.get("action") == "error":
                errs += 1
                print(f"  {folder}/{r['key']}: {r.get('error')}")
            else:
                ok += 1
    (d / "roll20.json").write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"성공 {ok}개, 오류 {errs}개")


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("build", "record"):
        sys.exit(__doc__)
    cmd, d = sys.argv[1], pathlib.Path(sys.argv[2])
    build(d, sys.argv[3:]) if cmd == "build" else record(d, sys.argv[3])
