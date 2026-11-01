#!/usr/bin/env python3
"""텍스트(URL 등)를 유니코드 반블록 QR 로 stdout 에 찍는다 — 응답 코드블록에 그대로 붙일 용도.

사용: qr.py [--light] <text>
  기본은 어두운 터미널 배경용(밝은 칸을 █ 로 칠한다). --light 는 밝은 배경용.

의존: segno(순수 파이썬). 없으면 ~/.cache/show-qr/pylib 에 pip --target 으로 한 번 받는다.
그것도 안 되면 qrencode CLI 로 대체한다.
"""
import os
import shutil
import subprocess
import sys

CACHE = os.path.join(os.path.expanduser("~"), ".cache", "show-qr", "pylib")


def load_segno():
    try:
        import segno  # noqa: F401
        return segno
    except ImportError:
        pass
    sys.path.insert(0, CACHE)
    try:
        import segno
        return segno
    except ImportError:
        pass
    r = subprocess.run(
        [sys.executable, "-m", "pip", "install", "-q", "--disable-pip-version-check",
         "--target", CACHE, "segno"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    if r.returncode != 0:
        return None
    import importlib
    importlib.invalidate_caches()
    try:
        import segno
        return segno
    except ImportError:
        return None


def render(matrix, light_bg):
    border = 2
    n = len(matrix)
    w = n + 2 * border
    rows = [[0] * w for _ in range(border)]
    rows += [[0] * border + [1 if v else 0 for v in r] + [0] * border for r in matrix]
    rows += [[0] * w for _ in range(border)]
    if len(rows) % 2:
        rows.append([0] * w)
    # 칠할 칸: 어두운 배경이면 밝은 모듈(0), 밝은 배경이면 어두운 모듈(1).
    ink = 1 if light_bg else 0
    glyph = {(True, True): "█", (True, False): "▀", (False, True): "▄", (False, False): " "}
    out = []
    for y in range(0, len(rows), 2):
        out.append("".join(
            glyph[(rows[y][x] == ink, rows[y + 1][x] == ink)] for x in range(w)
        ))
    return "\n".join(out)


def main():
    args = sys.argv[1:]
    light = False
    if args and args[0] == "--light":
        light, args = True, args[1:]
    if not args:
        print("usage: qr.py [--light] <text>", file=sys.stderr)
        return 2
    text = " ".join(args)

    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except AttributeError:
        pass

    segno = load_segno()
    if segno is not None:
        print(render(segno.make(text, error="l").matrix, light))
        return 0

    if shutil.which("qrencode"):
        # qrencode UTF8 은 어두운 배경용, UTF8i 는 반전.
        mode = "UTF8i" if light else "UTF8"
        r = subprocess.run(["qrencode", "-t", mode, "-m", "2", text],
                           stdout=subprocess.PIPE)
        sys.stdout.write(r.stdout.decode("utf-8"))
        return r.returncode

    print("ERROR: segno 를 받지 못했고 qrencode 도 없다", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
