# /// script
# requires-python = ">=3.10"
# dependencies = ["markdown"]
# ///
"""Roll20 핸드아웃 원본 디렉터리 <-> 페이지 JS 페이로드.

  uv run r20h.py build  DIR [KEY ...]   # 실행할 JS 를 DIR/.r20h-payload.js 에 쓴다
  uv run r20h.py record DIR RESULT.json  # upsert 결과의 id 를 DIR/roll20.json 에 기록

DIR 구조:
  roll20.json   {"campaign_id": 12345678, "handouts": {"<key>": "<roll20 id>"}}
  <key>.md      frontmatter(name, visible_to, avatar?, archived?) + 본문
                본문의 '<!-- gm -->' 줄 아래는 GM 메모(gmnotes)
"""
import json
import pathlib
import sys

import markdown

HERE = pathlib.Path(__file__).resolve().parent
GM_SPLIT = "<!-- gm -->"


def parse(path: pathlib.Path) -> dict:
    text = path.read_text(encoding="utf-8")
    meta = {}
    if text.startswith("---\n"):
        head, _, text = text[4:].partition("\n---\n")
        for line in head.splitlines():
            if ":" in line:
                k, _, v = line.partition(":")
                meta[k.strip()] = v.strip()
    if "name" not in meta:
        sys.exit(f"{path}: frontmatter 에 name 이 없다")
    body, _, gm = text.partition(GM_SPLIT)
    md = lambda s: markdown.markdown(s.strip(), extensions=["tables", "sane_lists"]) if s.strip() else ""
    vis = meta.get("visible_to", "gm")
    item = {
        "key": path.stem,
        "name": meta["name"],
        "notes": md(body),
        "gmnotes": md(gm),
        "visibleTo": vis if vis in ("gm", "all") else [x.strip() for x in vis.split(",") if x.strip()],
    }
    if "avatar" in meta:
        item["avatar"] = meta["avatar"]
    if "archived" in meta:
        item["archived"] = meta["archived"].lower() == "true"
    return item


def load_cfg(d: pathlib.Path) -> dict:
    cfg_path = d / "roll20.json"
    if not cfg_path.exists():
        sys.exit(f"{cfg_path} 가 없다 — {{\"campaign_id\": <게임 ID>, \"handouts\": {{}}}} 로 만든다")
    return json.loads(cfg_path.read_text(encoding="utf-8"))


def build(d: pathlib.Path, keys: list[str]) -> None:
    cfg = load_cfg(d)
    files = sorted(p for p in d.glob("*.md") if not keys or p.stem in keys)
    missing = set(keys) - {p.stem for p in files}
    if missing:
        sys.exit(f"원본 파일 없음: {', '.join(sorted(missing))}")
    items = []
    for p in files:
        it = parse(p)
        if it["key"] in cfg.get("handouts", {}):
            it["id"] = cfg["handouts"][it["key"]]
        items.append(it)
    js = (HERE / "r20h.js").read_text(encoding="utf-8")
    payload = json.dumps(items, ensure_ascii=False)
    out = d / ".r20h-payload.js"
    out.write_text(
        f"{js}\nawait R20H.upsert({json.dumps(cfg['campaign_id'])}, {payload});\n",
        encoding="utf-8",
    )
    print(f"{out} ({len(items)}개: {', '.join(i['key'] + ('' if 'id' in i else '(신규)') for i in items)})")


def record(d: pathlib.Path, result_path: str) -> None:
    cfg = load_cfg(d)
    results = json.loads(pathlib.Path(result_path).read_text(encoding="utf-8"))
    hs = cfg.setdefault("handouts", {})
    for r in results:
        if r.get("action") in ("created", "updated") and r.get("id"):
            hs[r["key"]] = r["id"]
    (d / "roll20.json").write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    errs = [r for r in results if r.get("action") == "error"]
    print(f"기록 {len(results) - len(errs)}개, 오류 {len(errs)}개")
    for r in errs:
        print(f"  {r['key']}: {r.get('error')}")


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("build", "record"):
        sys.exit(__doc__)
    cmd, d = sys.argv[1], pathlib.Path(sys.argv[2])
    build(d, sys.argv[3:]) if cmd == "build" else record(d, sys.argv[3])
