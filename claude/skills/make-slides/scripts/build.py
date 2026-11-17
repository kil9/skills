#!/usr/bin/env python3
"""덱 빌드. <프로젝트>/course.py 와 content/dNN.py 의 build(D) 를 모아 out/ 에 덱별 HTML 과 목차를 쓴다.

    python3 build.py <프로젝트>          # 전부
    python3 build.py <프로젝트> 3 4      # 덱 3·4 만(목차는 늘 다시 쓴다)
    python3 build.py <프로젝트> --outline  # OUTLINE.md 의 '빌드된 슬라이드' 절도 다시 쓴다

course.py 에 두는 것:
    TITLE = "강좌 이름"
    DECKS = {0: "오리엔테이션", 1: "첫 강의 제목", ...}   # 번호 → 제목. 덱 하나면 {1: "제목"}
    LECTURE = True                # 강의형(덱마다 요약·확인 문제 필수). 발표형이면 False
    def cover_figure(no): ...     # (선택) 표지 오른쪽에 둘 SVG HTML. 전체 지도에서 이 덱이 다루는 부분 강조 등
    def head_extra(no): ...       # (선택) <head> 에 더할 HTML(meta 등)
"""
import importlib
import importlib.util
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import deck  # noqa: E402
from deck import Deck, esc, page, table  # noqa: E402


def fname(no: int) -> str:
    return f"d{no:02d}.html"


def load_course(root: Path):
    spec = importlib.util.spec_from_file_location("course", root / "course.py")
    if spec is None or not (root / "course.py").exists():
        sys.exit(f"{root}/course.py 없음")
    c = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(c)
    return c


def main(argv):
    if not argv:
        sys.exit(__doc__)
    root = Path(argv[0]).resolve()
    rest = argv[1:]
    outline = "--outline" in rest
    want = {int(a) for a in rest if a != "--outline"}
    sys.path.insert(0, str(root))
    c = load_course(root)
    deck.COURSE = c.TITLE
    lecture = getattr(c, "LECTURE", True)
    out = root / "out"
    out.mkdir(exist_ok=True)

    built = {}
    for no, title in c.DECKS.items():
        try:
            mod = importlib.import_module(f"content.d{no:02d}")
        except ModuleNotFoundError:
            continue
        D = Deck(no, title, lecture)
        if hasattr(c, "cover_figure"):
            D.cover_figure = c.cover_figure(no) or ""
        mod.build(D)
        built[no] = D
    nos = sorted(built)
    for k, no in enumerate(nos):
        D = built[no]
        D.all_slides = [D.cover()] + D.slides
        if want and no not in want:
            continue
        prev = fname(nos[k - 1]) if k > 0 else ""
        nxt = fname(nos[k + 1]) if k + 1 < len(nos) else ""
        crumb = f"강의 {no} · {esc(D.title)}" if lecture and no else esc(D.title)
        extra = c.head_extra(no) if hasattr(c, "head_extra") else ""
        (out / fname(no)).write_text(page(f"{c.TITLE} {no} · {D.title}", D.all_slides, prev, nxt, crumb, extra), encoding="utf-8")
        print(f"wrote out/{fname(no)}  {len(D.all_slides)} slides")
    write_index(c, built, out)
    if outline:
        write_outline(root, built)


def write_index(c, built, out: Path):
    rows, total = [], 0
    for no, title in c.DECKS.items():
        D = built.get(no)
        n = len(D.all_slides) if D else 0
        total += n
        name = f'<a href="{fname(no)}">{esc(title)}</a>' if D else f"{esc(title)} <span class='muted'>(준비 중)</span>"
        goals = " · ".join(D.goals) if D else ""
        rows.append([str(no), name, goals, str(n) if n else "-"])
    t = table(["#", "제목", "마치면 할 수 있는 것", "장"], rows, align="lllr", widths=["6%", "28%", None, "6%"])
    fig = c.cover_figure(None) if hasattr(c, "cover_figure") else ""
    html = f"""<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{esc(c.TITLE)}</title><style>{deck.CSS}
body{{overflow:auto}} main{{max-width:1180px;margin:0 auto;padding:40px 16px 60px}} table.t td a{{color:var(--acc-ink);font-weight:650;text-decoration:none}}
.muted{{color:var(--mute)}} h1{{margin-bottom:6px}} .sub{{color:var(--fg2);margin:0 0 22px}}</style></head>
<body><main><h1>{esc(c.TITLE)}</h1><p class="sub">덱 {len(built)}개 · 총 {total}장 · 슬라이드는 ←/→ 로 넘깁니다</p>
{fig or ""}<div style="height:22px"></div>{t}</main></body></html>"""
    (out / "index.html").write_text(html, encoding="utf-8")
    print(f"wrote out/index.html  total {total} slides")


def write_outline(root: Path, built):
    """OUTLINE.md 의 '빌드된 슬라이드' 절을 실제 빌드 결과로 다시 쓴다(계획과 실물이 어긋나지 않게)."""
    p = root / "OUTLINE.md"
    head = p.read_text(encoding="utf-8").split("\n## 빌드된 슬라이드")[0].rstrip() if p.exists() else "# 목차"
    o = [head, "", "## 빌드된 슬라이드", "", "`build.py --outline` 이 쓴다. 손으로 고치지 않는다.", ""]
    for no in sorted(built):
        D = built[no]
        o.append(f"### {no}. {D.title} ({len(D.all_slides)}장)")
        o.append("")
        for i, sl in enumerate(D.all_slides, 1):
            o.append(f"{i}. " + re.sub(r"<[^>]+>", "", sl["title"]))
        o.append("")
    p.write_text("\n".join(o), encoding="utf-8")
    print("wrote OUTLINE.md")


if __name__ == "__main__":
    main(sys.argv[1:])
