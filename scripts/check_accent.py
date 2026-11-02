"""Kontroll: appens accentfärg ska faktiskt gälla och hänga ihop med ikonen.

Fångar felet där AccentColor fanns i Assets.xcassets men inte var kopplad i bygget, så att
appen visade systemets blå i stället för vår indigo. Kontrollerar att
  1. project.yml pekar ut AccentColor som global accentfärg,
  2. AccentColor har ljus och mörk variant (mörk ljusare än ljus),
  3. ikonens bakgrundsfärg är exakt AccentColor i ljust läge.
Kör: python3 scripts/check_accent.py"""
import json
import re
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Transkribera" / "Resources" / "Assets.xcassets"


def read_png_pixel(path: Path, x: int, y: int):
    """Läser en pixel ur en PNG (8 bitar, RGBA/RGB, inte interlaced) utan Pillow."""
    data = path.read_bytes()
    pos, idat, ihdr = 8, b"", None
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        pos += 12 + n
    w, h, depth, ctype, _, _, interlace = ihdr
    assert depth == 8 and ctype in (2, 6) and interlace == 0, "PNG-formatet stöds inte"
    bpp = 4 if ctype == 6 else 3
    raw, stride = zlib.decompress(idat), w * bpp
    prev = bytearray(stride)
    for row in range(y + 1):
        f = raw[row * (stride + 1)]
        line = bytearray(raw[row * (stride + 1) + 1:(row + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b, c = prev[i], (prev[i - bpp] if i >= bpp else 0)
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = line
    return tuple(prev[x * bpp:x * bpp + bpp])


def accent_variants():
    data = json.loads((ASSETS / "AccentColor.colorset" / "Contents.json").read_text(encoding="utf-8"))
    out = {}
    for e in data["colors"]:
        ap = {a["appearance"]: a["value"] for a in e.get("appearances", [])}
        if "contrast" in ap:
            continue
        c = e["color"]["components"]
        out["dark" if ap.get("luminosity") == "dark" else "light"] = tuple(
            round(float(c[k]) * 255) for k in ("red", "green", "blue"))
    return out


def check():
    errors = []
    yml = (ROOT / "project.yml").read_text(encoding="utf-8")
    if not re.search(r"^\s*ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME:\s*AccentColor\s*$", yml, re.M):
        errors.append("project.yml saknar ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor, "
                      "så appen visar systemets blå i stället för vår accentfärg")
    v = accent_variants()
    if set(v) != {"light", "dark"}:
        errors.append("AccentColor ska ha en ljus och en mörk variant")
        return errors
    if sum(v["dark"]) <= sum(v["light"]):
        errors.append("AccentColor i mörkt läge ska vara ljusare än i ljust")
    icon = ASSETS / "AppIcon.appiconset" / "icon_512x512@2x.png"
    px = read_png_pixel(icon, 300, 300)[:3]
    if tuple(px) != v["light"]:
        errors.append(f"Ikonens bakgrund {tuple(px)} är inte AccentColor i ljust läge {v['light']}")
    return errors


if __name__ == "__main__":
    errs = check()
    for e in errs:
        print("FEL:", e)
    if errs:
        sys.exit(1)
    print("Accentfärgen är kopplad och stämmer med ikonen.")
