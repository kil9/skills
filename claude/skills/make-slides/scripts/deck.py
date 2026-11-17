"""make-slides 덱 부품. 덱 하나 = <프로젝트>/content/dNN.py 의 build(D) 하나.

build.py 가 <프로젝트>/course.py 를 읽고 out/dNN.html 과 out/index.html 을 만든다.
슬라이드 하나는 표(table) 또는 정적 SVG(svg) 가 주인공이고, 문장은 say() 로 4줄까지만 단다.

    from deck import say, src, table, terms

    def build(D):
        D.set_goals("인덱스가 왜 읽기를 빠르게 하는지 말할 수 있다")
        D.section("인덱스")
        D.slide("인덱스는 정렬된 사본이라 찾을 때 전부 읽지 않는다",
                table(["찾는 법", "읽는 행"], [["전체 훑기", "1,000,000"], ["B-tree", "약 20"]], align="lr"),
                say("행이 100만 개여도 B-tree 는 높이만큼만 내려갑니다."))
        D.summary([("핵심", "기억할 것")])
        D.quiz([("질문", "정답", "풀이")])
"""
from __future__ import annotations

import html
import re

# build.py 가 course.py 를 읽어 채운다
COURSE = ""


def esc(s) -> str:
    return html.escape(str(s), quote=False)


# ------------------------------------------------------------------ HTML 부품
def say(*lines: str) -> str:
    """슬라이드 문장. 한 인자 = 한 줄. 슬라이드 전체에서 4줄까지(check.py 가 센다). HTML 허용."""
    return '<div class="say">' + "".join(f"<p>{l}</p>" for l in lines) + "</div>"


def src(text: str) -> str:
    """출처·조건 한 줄(작은 글씨). 문장 줄 수에 세지 않는다. 실측값에는 반드시 단다."""
    return f'<p class="src">출처 · {text}</p>'


def aside(title: str, *lines: str, ref: str = "") -> str:
    """곁들임 패널: 본문과 출처가 다른 정보(외부 발표·운영 현황·계획). 한 인자 = 한 줄, 3줄까지(따로 센다).
    바탕 톤과 굵은 제목 줄로만 구분한다. 색 띠·칩·색 테두리를 더하지 않는다."""
    head = f'<h3>{title}{f"<span>{ref}</span>" if ref else ""}</h3>'
    return '<div class="aside">' + head + "".join(f"<p>{l}</p>" for l in lines) + "</div>"


def table(head, rows, align: str = "", cls: str = "", hl=(), widths=None) -> str:
    """표. 셀은 HTML 문자열. align 은 열마다 l/r/c (예: "lrr"). hl 은 강조할 행 번호들(0부터).
    widths 는 열 너비 목록(예: ["30%", None, None]). cls="sm" 은 행이 많을 때."""
    def a(i):
        c = align[i] if i < len(align) else "l"
        return {"l": "", "r": ' class="r"', "c": ' class="c"'}[c]

    o = [f'<table class="t {cls}">']
    if widths:
        o.append("<colgroup>" + "".join(f'<col style="width:{w}">' if w else "<col>" for w in widths) + "</colgroup>")
    if head:
        o.append("<thead><tr>" + "".join(f"<th{a(i)}>{h}</th>" for i, h in enumerate(head)) + "</tr></thead>")
    o.append("<tbody>")
    for j, r in enumerate(rows):
        tr = ' class="hl"' if j in hl else ""
        o.append(f"<tr{tr}>" + "".join(f"<td{a(i)}>{c}</td>" for i, c in enumerate(r)) + "</tr>")
    o.append("</tbody></table>")
    return "".join(o)


def terms(rows) -> str:
    """새 용어 풀이 표. rows = [(용어, 한 줄 뜻, 익숙한 개념에 빗대면), ...]. 빗댄 말은 셋째 열에만 둔다."""
    return table(["새 용어", "뜻", "익숙한 것에 빗대면"],
                 [[f"<dfn>{t}</dfn>", m, l] for t, m, l in rows], cls="terms", widths=["18%", "47%", "35%"])


def cols(*parts, ratio: str = "") -> str:
    """가로로 나란히. ratio 예: "3fr 2fr"."""
    st = f' style="grid-template-columns:{ratio}"' if ratio else f' style="grid-template-columns:repeat({len(parts)},1fr)"'
    return f'<div class="cols"{st}>' + "".join(f"<div>{p}</div>" for p in parts) + "</div>"


def kpis(items) -> str:
    """큰 숫자 띠. items = [(값, 설명), ...]. 표·그림을 대신하지 않는다(곁들임)."""
    return '<div class="kpis">' + "".join(f"<div><b>{v}</b><span>{d}</span></div>" for v, d in items) + "</div>"


def code(text: str) -> str:
    """설정·명령 원문 블록. 줄마다 풀이가 필요하면 table 로 쓴다."""
    return f'<pre class="code">{esc(text)}</pre>'


# ------------------------------------------------------------------ SVG 부품
# 좌표는 viewBox 기준. 색은 클래스로만 준다(라이트/다크 토큰은 CSS).
# 상자 클래스: "" 기본 · "acc" 강조 · "warn" 주의 · "bad" 나쁨 · "ok" 좋음 · "mute" 흐림 · "plain" 테두리만 · "ghost" 점선
_SVG_SEQ = 0


def svg(w: int, h: int, *parts: str, label: str = "그림", maxh: int | None = None) -> str:
    global _SVG_SEQ
    st = f' style="max-height:{maxh}px"' if maxh else ""
    defs = ('<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
            '<path d="M0,0 L10,5 L0,10 z" class="ah"/></marker>'
            '<marker id="aha" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
            '<path d="M0,0 L10,5 L0,10 z" class="aha"/></marker></defs>')
    # 화살촉 marker id 는 문서 전체에서 유일해야 한다. 같은 id 가 여럿이면 브라우저가 숨은(display:none) 슬라이드의
    # marker 를 먼저 잡아 둘째 장부터 화살촉이 사라진다.
    _SVG_SEQ += 1
    k = _SVG_SEQ
    inner = (defs + "".join(parts)).replace('id="ah"', f'id="ah{k}"').replace('id="aha"', f'id="aha{k}"')
    inner = inner.replace("url(#ah)", f"url(#ah{k})").replace("url(#aha)", f"url(#aha{k})")
    return f'<figure class="fig"><svg viewBox="0 0 {w} {h}" role="img" aria-label="{esc(label)}"{st}>{inner}</svg></figure>'


def txt(x, y, s, cls: str = "", anchor: str = "start", size: float | None = None) -> str:
    st = f' style="font-size:{size}px"' if size else ""
    c = f' class="{cls}"' if cls else ""
    return f'<text x="{x}" y="{y}"{c} text-anchor="{anchor}"{st}>{s}</text>'


def box(x, y, w, h, title: str = "", sub=None, cls: str = "", rx: int = 8, size: float | None = None) -> str:
    """제목(굵게)과 보조 줄(여러 줄 가능)을 가운데 정렬한 상자."""
    subs = [] if sub is None else ([sub] if isinstance(sub, str) else list(sub))
    o = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" class="bx {cls}"/>']
    n = (1 if title else 0) + len(subs)
    lh = 20
    y0 = y + h / 2 - (n - 1) * lh / 2 + 6
    k = 0
    if title:
        o.append(txt(x + w / 2, y0, title, "b", "middle", size))
        k = 1
    for i, s in enumerate(subs):
        o.append(txt(x + w / 2, y0 + (k + i) * lh, s, "sm", "middle"))
    return "".join(o)


def arrow(x1, y1, x2, y2, label: str = "", cls: str = "", dash: bool = False, lx=None, ly=None) -> str:
    """화살표. cls="acc" 면 강조색. label 은 중간 위에 작게."""
    d = ' stroke-dasharray="5 4"' if dash else ""
    m = "aha" if "acc" in cls else "ah"
    o = [f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" class="ar {cls}"{d} marker-end="url(#{m})"/>']
    if label:
        o.append(txt(lx if lx is not None else (x1 + x2) / 2, ly if ly is not None else (y1 + y2) / 2 - 7, label, "sm", "middle"))
    return "".join(o)


def path(d: str, cls: str = "", arrowhead: bool = False, dash: bool = False) -> str:
    da = ' stroke-dasharray="5 4"' if dash else ""
    m = f' marker-end="url(#{"aha" if "acc" in cls else "ah"})"' if arrowhead else ""
    return f'<path d="{d}" class="ar {cls}"{da}{m} fill="none"/>'


def line(x1, y1, x2, y2, cls: str = "grid") -> str:
    return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" class="{cls}"/>'


def rect(x, y, w, h, cls: str = "", rx: int = 3) -> str:
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" class="bx {cls}"/>'


def hbars(items, w: int = 1100, unit: str = "", maxv=None, label: str = "막대 그래프", bar_h: int = 26, lw: int = 260) -> str:
    """가로 막대 그래프. items = [(이름, 값, cls), ...]. 값 텍스트는 막대 끝에.
    막대가 많아 제목과 겹치면 bar_h 를 줄인다(그림의 높이 = 항목 수 × (bar_h + 12))."""
    maxv = maxv or max(v for _, v, *_ in items)
    gap = 12
    h = len(items) * (bar_h + gap) + 10
    o = []
    for i, it in enumerate(items):
        name, v = it[0], it[1]
        c = it[2] if len(it) > 2 else "acc"
        y = 6 + i * (bar_h + gap)
        bw = max(2, (w - lw - 120) * v / maxv)
        o.append(txt(lw - 12, y + bar_h / 2 + 6, name, "", "end"))
        o.append(rect(lw, y, bw, bar_h, c))
        o.append(txt(lw + bw + 10, y + bar_h / 2 + 6, f"{v:,}{unit}" if isinstance(v, (int, float)) else v, "mono b"))
    return svg(w, h, *o, label=label)


# ------------------------------------------------------------------ 덱
class Deck:
    def __init__(self, no: int, title: str, lecture: bool = True):
        self.no = no
        self.title = title
        self.lecture = lecture
        self.goals: list[str] = []
        self.slides: list[dict] = []
        self.cur_section = ""
        self.cover_figure = ""

    def set_goals(self, *goals: str):
        """표지의 '이 강의를 마치면' 2-4개. 동사로 끝나는 할 수 있는 일로 쓴다."""
        self.goals = list(goals)

    def section(self, name: str):
        """이후 슬라이드의 머리 글씨(eyebrow)."""
        self.cur_section = name

    def slide(self, title: str, *body: str, eyebrow: str | None = None, kind: str = ""):
        """title 은 그 장의 결론 한 문장('-다'). body 는 부품 HTML 들."""
        self.slides.append({"title": title, "body": "".join(body),
                            "eyebrow": eyebrow if eyebrow is not None else self.cur_section, "kind": kind})

    def summary(self, rows):
        """요약 한 장. rows = [(핵심, 기억할 것), ...]"""
        self.slide(f"{self.title} 요약" if not self.lecture or not self.no else f"강의 {self.no} 요약",
                   table(["핵심", "기억할 것"], rows, widths=["30%", None]), eyebrow="요약", kind="summary")

    def quiz(self, items):
        """확인 문제 + 정답 두 장. items = [(질문, 정답, 풀이), ...]. 풀이에는 숫자의 출처까지 쓴다."""
        self.slide("확인 문제", table(["#", "질문"], [[str(i + 1), q] for i, (q, _, _) in enumerate(items)],
                                       cls="quiz", widths=["6%", None]),
                   say("답을 떠올린 뒤 다음 장에서 맞춰 봅니다."), eyebrow="확인 문제", kind="quiz")
        self.slide("확인 문제 정답", table(["#", "정답", "풀이"], [[str(i + 1), f"<b>{a}</b>", w] for i, (_, a, w) in enumerate(items)],
                                         cls="quiz", widths=["6%", "34%", None]),
                   eyebrow="확인 문제", kind="answer")

    def cover(self):
        """표지. 목표 표 + (있으면) 덱 설정의 cover_figure."""
        goals = table(["이 강의를 마치면" if self.lecture else "이 발표에서"], [[g] for g in self.goals], cls="goals") if self.goals else ""
        if goals and self.cover_figure:
            body = cols(goals, self.cover_figure, ratio="2fr 3fr")
        else:
            body = goals or self.cover_figure
        eb = f"{COURSE} · 강의 {self.no}" if self.lecture and self.no else COURSE
        return {"title": self.title, "body": body, "eyebrow": eb, "kind": "cover"}


# ------------------------------------------------------------------ 페이지
CSS = r"""
:root{--bg:#f6f7f9;--paper:#ffffff;--fg:#1b1f27;--fg2:#4a5160;--mute:#8a909c;--line:#dfe2e8;--line2:#c4c9d2;
--soft:#f1f3f6;--acc:#2f62d8;--acc-soft:#e6edfc;--acc-ink:#1d45a8;--warn:#b7791f;--warn-soft:#fbf1df;
--bad:#c2410c;--bad-soft:#fde8de;--ok:#17803d;--ok-soft:#e1f3e7;--code:#f3f4f7;
--sans:"Pretendard","Noto Sans KR","Apple SD Gothic Neo",system-ui,sans-serif;--mono:"JetBrains Mono","D2Coding",ui-monospace,monospace}
@media (prefers-color-scheme: dark){:root{--bg:#111418;--paper:#181c22;--fg:#e6e9ef;--fg2:#aeb4c0;--mute:#737a87;--line:#2a3039;--line2:#3a414c;
--soft:#1f242c;--acc:#7aa2ff;--acc-soft:#1c2a4a;--acc-ink:#b9ccff;--warn:#e0a84a;--warn-soft:#3a2d16;--bad:#ff8a5c;--bad-soft:#3d2218;
--ok:#5cc985;--ok-soft:#173222;--code:#1f242c}}
*{box-sizing:border-box}
html,body{margin:0;height:100%;background:var(--bg);color:var(--fg);font-family:var(--sans)}
body{overflow:hidden}
#stage{position:absolute;left:50%;top:50%;width:1280px;height:720px;transform-origin:center center}
section.s{position:absolute;inset:0;display:none;flex-direction:column;padding:34px 48px 40px;background:var(--paper);
 border:1px solid var(--line);border-radius:6px;font-size:21px;line-height:1.5}
section.s.on{display:flex}
.eb{font-family:var(--mono);font-size:13px;letter-spacing:.08em;color:var(--acc);font-weight:600;margin-bottom:4px}
h1{font-size:40px;margin:0 0 16px;letter-spacing:-.02em;line-height:1.2}
h2{font-size:29px;margin:0 0 16px;letter-spacing:-.015em;line-height:1.28;font-weight:750}
.body{flex:1;min-height:0;display:flex;flex-direction:column;gap:14px;justify-content:center}
.say p{margin:0;color:var(--fg2);font-size:19px;line-height:1.55}
.say p b{color:var(--fg)}
p.src{margin:0;font-size:13px;color:var(--mute)}
.cols{display:grid;gap:26px;align-items:center}
.cols>div{min-width:0;display:flex;flex-direction:column;gap:12px}
table.t{width:100%;border-collapse:collapse;font-size:18px;line-height:1.4}
table.t th{text-align:left;font-weight:650;color:var(--fg2);font-size:15px;padding:7px 10px;border-bottom:2px solid var(--line2);background:var(--soft)}
table.t td{padding:7px 10px;border-bottom:1px solid var(--line);vertical-align:top}
table.t .r{text-align:right;font-variant-numeric:tabular-nums}
table.t .c{text-align:center}
table.t td.r{font-family:var(--mono);font-size:.94em}
table.t tr.hl td{background:var(--acc-soft)}
table.t code,.say code{font-family:var(--mono);font-size:.86em;background:var(--code);padding:1px 5px;border-radius:4px}
table.t dfn{font-style:normal;font-weight:700;color:var(--acc-ink)}
table.t.sm{font-size:15.5px} table.t.sm td,table.t.sm th{padding:5px 8px}
table.t.goals td{font-size:18px}
table.t.quiz td:first-child{font-family:var(--mono);color:var(--acc);font-weight:700}
.aside{background:var(--soft);border-radius:6px;padding:10px 16px 12px}
.aside h3{margin:0 0 2px;font-size:15px;font-weight:700;color:var(--fg);display:flex;gap:12px;align-items:baseline}
.aside h3 span{font-weight:400;font-size:13px;color:var(--mute)}
.aside p{margin:0;font-size:17px;line-height:1.5;color:var(--fg2)} .aside p b{color:var(--fg)}
.kpis{display:flex;gap:12px}
.kpis>div{flex:1;border:1px solid var(--line);border-radius:8px;padding:10px 14px;background:var(--soft)}
.kpis b{display:block;font-family:var(--mono);font-size:28px;font-weight:650;color:var(--acc-ink)}
.kpis span{display:block;font-size:14px;color:var(--fg2)}
pre.code{margin:0;font-family:var(--mono);font-size:14.5px;line-height:1.5;background:var(--code);border:1px solid var(--line);border-radius:6px;padding:10px 14px;white-space:pre;overflow:hidden}
figure.fig{margin:0}
figure.fig svg{display:block;width:100%;height:auto;margin:0 auto;font-family:var(--sans);font-size:16px}
svg text{fill:var(--fg)} svg .sm{font-size:13.5px;fill:var(--fg2)} svg .b{font-weight:700} svg .mono{font-family:var(--mono)}
svg .mut{fill:var(--mute)} svg .acct{fill:var(--acc-ink)} svg .badt{fill:var(--bad)} svg .okt{fill:var(--ok)}
svg .bx{fill:var(--soft);stroke:var(--line2);stroke-width:1.2}
svg .bx.acc{fill:var(--acc-soft);stroke:var(--acc)} svg .bx.warn{fill:var(--warn-soft);stroke:var(--warn)}
svg .bx.bad{fill:var(--bad-soft);stroke:var(--bad)} svg .bx.ok{fill:var(--ok-soft);stroke:var(--ok)}
svg .bx.mute{fill:var(--paper);stroke:var(--line);opacity:.75} svg .bx.plain{fill:var(--paper)}
svg .bx.solid{fill:var(--acc);stroke:var(--acc)} svg .bx.ghost{fill:none;stroke:var(--line2);stroke-dasharray:5 4}
svg .ar{stroke:var(--fg2);stroke-width:1.6;fill:none} svg .ar.acc{stroke:var(--acc);stroke-width:2.2}
svg .ar.bad{stroke:var(--bad)} svg .ah{fill:var(--fg2)} svg .aha{fill:var(--acc)}
svg .grid{stroke:var(--line);stroke-width:1}
section.cover h1{font-size:44px}
#bar{position:fixed;left:0;right:0;top:0;height:30px;display:flex;align-items:center;justify-content:space-between;padding:0 14px;
 font-family:var(--mono);font-size:12.5px;color:var(--fg2);z-index:3}
#bar a{color:var(--fg2);text-decoration:none} #bar a:hover{color:var(--acc)}
#prog{position:fixed;left:0;bottom:0;height:3px;background:var(--acc);z-index:3}
@media print{body{overflow:visible}#bar,#prog{display:none}#stage{position:static;transform:none!important}
 section.s{display:flex;position:relative;page-break-after:always;margin:0 0 8px}}
"""

# ?check 로 열면 장마다 넘침(본문이 제목 쪽으로 밀려 겹침)과 SVG 글자 잘림을 재서 #__check 에 JSON 으로 쓴다(check.py --render).
JS = r"""
const S=[...document.querySelectorAll('section.s')],N=S.length,st=document.getElementById('stage');
if(location.search.includes('check')){const r=[];S.forEach((s,k)=>{s.classList.add('on');
 const b=s.querySelector('.body'),h=s.querySelector('h1,h2');
 if(b&&b.scrollHeight>b.clientHeight+2)r.push([k+1,'본문 넘침 '+(b.scrollHeight-b.clientHeight)+'px (제목과 겹치거나 아래가 잘림)']);
 if(b&&h&&b.firstElementChild&&b.firstElementChild.getBoundingClientRect().top<h.getBoundingClientRect().bottom-1)r.push([k+1,'본문이 제목과 겹침']);
 s.querySelectorAll('svg').forEach(g=>{const v=g.viewBox.baseVal;if(!v)return;g.querySelectorAll('text').forEach(t=>{const q=t.getBBox();
  if(q.x<v.x-1||q.y<v.y-1||q.x+q.width>v.x+v.width+1||q.y+q.height>v.y+v.height+1)r.push([k+1,'svg 글자 잘림: '+t.textContent.slice(0,30)])})});
 s.classList.remove('on')});const p=document.createElement('pre');p.id='__check';p.textContent=JSON.stringify(r);document.body.appendChild(p)}
let i=parseInt(location.hash.slice(1));i=location.hash==='#last'?N-1:Math.min(Math.max((isNaN(i)?1:i)-1,0),N-1);
function fit(){const k=Math.min(innerWidth/1300,(innerHeight-40)/740);st.style.transform=`translate(-50%,-50%) scale(${k})`}
function show(n){S[i].classList.remove('on');i=n;S[i].classList.add('on');history.replaceState(null,'','#'+(i+1));
 document.getElementById('pos').textContent=(i+1)+' / '+N;document.getElementById('prog').style.width=((i+1)/N*100)+'%'}
function go(d){const n=i+d;if(n<0){if(PREV)location.href=PREV+'#last';return}if(n>=N){if(NEXT)location.href=NEXT;return}show(n)}
addEventListener('keydown',e=>{if(e.altKey||e.ctrlKey||e.metaKey)return;
 if(['ArrowRight','PageDown',' ','Enter'].includes(e.key)){e.preventDefault();go(1)}
 else if(['ArrowLeft','PageUp','Backspace'].includes(e.key)){e.preventDefault();go(-1)}
 else if(e.key==='Home')show(0);else if(e.key==='End')show(N-1)});
addEventListener('resize',fit);fit();S[i].classList.add('on');show(i);
"""


def render_slide(s: dict, i: int) -> str:
    h = "h1" if s["kind"] == "cover" else "h2"
    eb = f'<div class="eb">{s["eyebrow"]}</div>' if s["eyebrow"] else ""
    return (f'<section class="s {s["kind"]}" data-kind="{s["kind"]}" data-n="{i + 1}">{eb}'
            f'<{h}>{s["title"]}</{h}><div class="body">{s["body"]}</div></section>')


def page(title: str, slides: list[dict], prev: str, nxt: str, crumb: str, head_extra: str = "") -> str:
    body = "\n".join(render_slide(s, i) for i, s in enumerate(slides))
    return f"""<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">{head_extra}
<title>{esc(title)}</title><style>{CSS}</style></head>
<body><div id="bar"><span><a href="index.html">{esc(COURSE)}</a> · {crumb}</span><span id="pos"></span></div>
<div id="stage">
{body}
</div><div id="prog"></div>
<script>const PREV={prev!r},NEXT={nxt!r};{JS}</script></body></html>
"""


def strip_tags(s: str) -> str:
    return re.sub(r"<[^>]+>", "", s)
