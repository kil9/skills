#!/usr/bin/env python3
"""슬라이드 캡처(눈 검수용). playwright 가 받아 둔 chromium headless shell 을 그대로 쓴다.

    python3 shot.py <프로젝트> 3            # 덱 3 전 장 → ~/.cache/make-slides/shots/<프로젝트이름>/d03-NN.png
    python3 shot.py <프로젝트> 3 5 7        # 덱 3 의 5·7 장만
"""
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check import headless  # noqa: E402

if len(sys.argv) < 3:
    sys.exit(__doc__)
root = Path(sys.argv[1]).resolve()
no = int(sys.argv[2])
f = root / "out" / f"d{no:02d}.html"
n_total = len(re.findall(r'<section class="s ', f.read_text(encoding="utf-8")))
pages = [int(a) for a in sys.argv[3:]] or range(1, n_total + 1)
b = headless()
if not b:
    sys.exit("headless chromium 없음: `python3 -m playwright install chromium-headless-shell`")
shots = Path.home() / ".cache/make-slides/shots" / root.name
shots.mkdir(parents=True, exist_ok=True)
for n in pages:
    png = shots / f"d{no:02d}-{n:02d}.png"
    subprocess.run([b, "--headless", "--hide-scrollbars", "--window-size=1300,780", "--force-device-scale-factor=1",
                    f"--screenshot={png}", f"file://{f}#{n}"], check=True, capture_output=True, timeout=60)
    print(png)
