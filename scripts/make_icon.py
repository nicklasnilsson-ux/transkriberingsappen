"""Ritar appikonen (indigo ruta, ljudvåg som blir textrader) och skriver alla storlekar.

Ikonen är vår egen och ritas här, inte från ett bibliotek. Färgen är appens accentfärg
(AccentColor, ljust läge). Kör: python3 scripts/make_icon.py   (kräver Pillow)
scripts/check_accent.py kontrollerar att ikonens färg och accentfärgen hänger ihop."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "Transkribera/Resources/Assets.xcassets/AppIcon.appiconset"
INDIGO = (0x4F, 0x46, 0xE5)
S = 4                      # överupplösning för mjuka kanter
BARS = dict(h=[110, 230, 340, 230, 110], w=44, pitch=68)
LINES = dict(len=[250, 250, 160], th=44, pitch=100)
GAP = 48


def squircle_points(n=5.0, a=412.0, c=512.0, steps=720):
    import math
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        cs, sn = math.cos(t), math.sin(t)
        pts.append(((c + a * math.copysign(abs(cs) ** (2 / n), cs)) * S,
                    (c + a * math.copysign(abs(sn) ** (2 / n), sn)) * S))
    return pts


def pill(d, x, y, w, h):
    d.rounded_rectangle([x * S, y * S, (x + w) * S, (y + h) * S], radius=min(w, h) / 2 * S, fill=(255, 255, 255, 255))


def master():
    size = 1024 * S
    body = Image.new("L", (size, size), 0)
    ImageDraw.Draw(body).polygon(squircle_points(), fill=255)
    shadow = Image.new("L", (size, size), 0)
    shadow.paste(body, (0, 14 * S))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14 * S)).point(lambda v: int(v * 0.28))
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    img.paste(Image.new("RGBA", (size, size), (0, 0, 0, 255)), mask=shadow)
    flat = Image.new("RGBA", (size, size), INDIGO + (255,))
    img.paste(flat, mask=body)
    d = ImageDraw.Draw(img)
    bw = (len(BARS["h"]) - 1) * BARS["pitch"] + BARS["w"]
    x0 = 512 - (bw + GAP + max(LINES["len"])) / 2
    for i, h in enumerate(BARS["h"]):
        pill(d, x0 + i * BARS["pitch"], 512 - h / 2, BARS["w"], h)
    span = (len(LINES["len"]) - 1) * LINES["pitch"] + LINES["th"]
    for i, ln in enumerate(LINES["len"]):
        pill(d, x0 + bw + GAP, 512 - span / 2 + i * LINES["pitch"], ln, LINES["th"])
    return img


if __name__ == "__main__":
    big = master()
    for name, px in [("16x16@1x", 16), ("16x16@2x", 32), ("32x32@1x", 32), ("32x32@2x", 64),
                     ("128x128@1x", 128), ("128x128@2x", 256), ("256x256@1x", 256), ("256x256@2x", 512),
                     ("512x512@1x", 512), ("512x512@2x", 1024)]:
        big.resize((px, px), Image.LANCZOS).save(OUT / f"icon_{name}.png")
    print("Ikonen skriven till", OUT)
