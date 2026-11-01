"""Kontroll: färgerna i Assets.xcassets ska vara läsbara som text.

Varje färguppsättning (AccentColor, WarningColor …) ska ha minst 4,5:1 mot appens
bakgrund: vit i ljust läge och #1E1E1E i mörkt. Varianterna för Öka kontrast ska ha
minst 7:1. Dessutom får `.orange` inte användas på text (systemets orange ger 2,2:1 på vitt).
Kör: python3 scripts/check_colors.py"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Transkribera" / "Resources" / "Assets.xcassets"
LIGHT_BG, DARK_BG = (1.0, 1.0, 1.0), (0x1E / 255,) * 3


def luminance(rgb):
    def lin(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def variants(colorset: Path):
    data = json.loads((colorset / "Contents.json").read_text(encoding="utf-8"))
    for entry in data["colors"]:
        values = {a["appearance"]: a["value"] for a in entry.get("appearances", [])}
        c = entry["color"]["components"]
        yield ("dark" if values.get("luminosity") == "dark" else "light",
               values.get("contrast") == "high",
               tuple(float(c[k]) for k in ("red", "green", "blue")))


def check_colorsets():
    errors = []
    for colorset in sorted(ASSETS.glob("*.colorset")):
        found = set()
        for mode, high, rgb in variants(colorset):
            found.add((mode, high))
            ratio = contrast(rgb, DARK_BG if mode == "dark" else LIGHT_BG)
            need = 7.0 if high else 4.5
            if ratio < need:
                errors.append(f"{colorset.stem}: {mode}{' hög kontrast' if high else ''} ger {ratio:.2f}:1, kravet är {need}:1")
        for want in [(m, h) for m in ("light", "dark") for h in (False, True)]:
            if want not in found:
                errors.append(f"{colorset.stem}: saknar variant {want}")
    return errors


# foregroundStyle(.orange) / foregroundColor(.orange) på text, etiketter och ikoner med text.
ORANGE = re.compile(r"foreground(?:Style|Color)\(\s*\.orange\s*\)")


def check_orange():
    return [f"{p.relative_to(ROOT)}:{n}: .orange på text, använd Color.warning"
            for p in sorted((ROOT / "Transkribera").rglob("*.swift"))
            for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1)
            if ORANGE.search(line)]


def main():
    errors = check_colorsets() + check_orange()
    if not list(ASSETS.glob("*.colorset")):
        errors.append("Hittar inga färguppsättningar")
    for e in errors:
        print("FEL:", e)
    if errors:
        sys.exit(1)
    print("Färgerna är läsbara.")


if __name__ == "__main__":
    main()
