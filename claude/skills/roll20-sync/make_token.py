# /// script
# requires-python = ">=3.11"
# dependencies = ["opencv-python-headless>=4.9,<5", "numpy", "pillow"]
# ///
"""초상에서 얼굴을 찾아 롤20 토큰(정사각형 크롭, 원형)을 만든다. 원본 그림은 건드리지 않는다.

uv run make_token.py <초상...> --out <디렉터리> [--style square|round|both] [--size 280]
얼굴은 애니·일러스트용 LBP 검출기(lbpcascade_animeface)로 먼저 찾고, 못 찾으면 YuNet, 그래도 없으면
위쪽 1/3 중앙을 쓴다. 모델 파일은 ~/.cache/token-face/ 에 없으면 받는다.
"""
import argparse, sys, urllib.request
from pathlib import Path
import cv2, numpy as np
from PIL import Image, ImageDraw, ImageFilter

CACHE = Path.home() / ".cache/token-face"
MODELS = {
    "lbpcascade_animeface.xml": "https://raw.githubusercontent.com/nagadomi/lbpcascade_animeface/master/lbpcascade_animeface.xml",
    "yunet.onnx": "https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx",
}

def model(name):
    p = CACHE / name
    if not p.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(MODELS[name], p)
    return str(p)

def detect(img):
    """(x, y, w, h, 방법) — 가장 큰 얼굴 하나."""
    h, w = img.shape[:2]
    gray = cv2.equalizeHist(cv2.cvtColor(img, cv2.COLOR_BGR2GRAY))
    casc = cv2.CascadeClassifier(model("lbpcascade_animeface.xml"))
    faces = casc.detectMultiScale(gray, 1.05, 4, minSize=(w // 10, w // 10))
    if len(faces):
        x, y, fw, fh = max(faces, key=lambda f: f[2] * f[3])
        return x, y, fw, fh, "anime"
    yn = cv2.FaceDetectorYN.create(model("yunet.onnx"), "", (w, h), 0.6)
    _, res = yn.detect(img)
    if res is not None and len(res):
        x, y, fw, fh = max(res, key=lambda r: r[2] * r[3])[:4]
        return int(x), int(y), int(fw), int(fh), "yunet"
    s = w // 3
    return w // 2 - s // 2, h // 6, s, s, "fallback"

def square_box(img_w, img_h, x, y, fw, fh, zoom):
    """얼굴 박스 중심, 한 변 = 얼굴 크기 × zoom 인 정사각형. 그림 밖으로 나가면 안쪽으로 민다."""
    side = int(fw * zoom)  # 세로 박스는 수염·턱까지 잡아 들쭉날쭉해 너비만 본다
    side = min(side, img_w, img_h)
    cx, cy = x + fw / 2, y + fh / 2 + fw * 0.05  # 턱·목이 조금 들어오게 살짝 아래로
    left = int(round(min(max(cx - side / 2, 0), img_w - side)))
    top = int(round(min(max(cy - side / 2, 0), img_h - side)))
    return left, top, left + side, top + side

def round_token(sq, ring=(196, 160, 92), size=None):
    n = sq.width
    ss = 4  # 가장자리 매끄럽게 하려고 크게 그려 줄인다
    N = n * ss
    border = int(N * 0.045)
    out = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).ellipse((border, border, N - border, N - border), fill=255)
    out.paste(sq.resize((N, N), Image.LANCZOS).convert("RGBA"), (0, 0), mask)
    d = ImageDraw.Draw(out)
    d.ellipse((0, 0, N - 1, N - 1), outline=(20, 16, 12, 255), width=int(N * 0.012))
    d.ellipse((int(N * 0.01), int(N * 0.01), N - int(N * 0.01), N - int(N * 0.01)), outline=ring + (255,), width=border)
    d.ellipse((border, border, N - border, N - border), outline=(20, 16, 12, 230), width=int(N * 0.008))
    return out.resize((n, n), Image.LANCZOS)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("images", nargs="+")
    ap.add_argument("--out", required=True)
    ap.add_argument("--style", choices=["square", "round", "both"], default="both")
    ap.add_argument("--size", type=int, default=280)
    ap.add_argument("--zoom", type=float, default=1.9, help="토큰 한 변 / 얼굴 크기")
    a = ap.parse_args()
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    for p in map(Path, a.images):
        img = cv2.imread(str(p))
        if img is None:
            print(f"skip {p}", file=sys.stderr); continue
        x, y, fw, fh, how = detect(img)
        box = square_box(img.shape[1], img.shape[0], x, y, fw, fh, a.zoom)
        sq = Image.open(p).convert("RGB").crop(box)  # 정사각형을 잘라 축소만 하므로 종횡비 유지
        if sq.width > a.size:
            sq = sq.resize((a.size, a.size), Image.LANCZOS)
        print(f"{p.name}\t{how}\tface={x},{y},{fw}x{fh}\tcrop={box}")
        if a.style in ("square", "both"):
            sq.save(out / f"{p.stem}-token.jpg", quality=90, subsampling=0)
        if a.style in ("round", "both"):
            round_token(sq).save(out / f"{p.stem}-token-round.png")

if __name__ == "__main__":
    main()
