"""Kontroll: färgerna i Assets.xcassets ska vara läsbara.

Textfärgerna (TEXT) ska ha minst 4,5:1 mot varje bakgrund (BACKGROUNDS) i samma läge, och
varianterna för Öka kontrast minst 7:1. Texten på den neutrala (svarta) knappen ska ha samma
kontrast mot knappen. Linjerna ska synas mot bakgrunden. Varje färg som koden hämtar med
`Color("Namn")` ska finnas som färguppsättning med alla fyra varianter. Dessutom får `.orange`
inte användas på text (systemets orange ger 2,2:1 på vitt).
Kör: python3 scripts/check_colors.py"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Transkribera" / "Resources" / "Assets.xcassets"
LIGHT_BG, DARK_BG = (1.0, 1.0, 1.0), (0x1C / 255, 0x1C / 255, 0x21 / 255)
TEXT = ["AccentColor", "WarningColor", "SuccessColor", "TextPrimary", "TextSecondary", "TextTertiary"]
BACKGROUNDS = ["AppBackground", "SidebarBackground", "SurfaceBackground", "ChipBackground"]
THEME = ROOT / "Transkribera" / "Views" / "Theme.swift"


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


def load_all():
    """{(namn, läge, hög kontrast): rgb} för alla färguppsättningar."""
    return {(cs.stem, mode, high): rgb
            for cs in sorted(ASSETS.glob("*.colorset"))
            for mode, high, rgb in variants(cs)}


def check_colorsets():
    errors = []
    colors = load_all()
    names = {k[0] for k in colors}
    for name in sorted(names):
        for want in [(m, h) for m in ("light", "dark") for h in (False, True)]:
            if (name, *want) not in colors:
                errors.append(f"{name}: saknar variant {want}")
    if errors:
        return errors
    for mode in ("light", "dark"):
        for high in (False, True):
            label = f"{mode}{' hög kontrast' if high else ''}"
            need = 7.0 if high else 4.5
            for text in TEXT:
                for bg in BACKGROUNDS:
                    if text not in names or bg not in names:
                        errors.append(f"färguppsättningen {text if text not in names else bg} saknas")
                        continue
                    ratio = contrast(colors[(text, mode, high)], colors[(bg, mode, high)])
                    if ratio < need:
                        errors.append(f"{text} på {bg}: {label} ger {ratio:.2f}:1, kravet är {need}:1")
            if {"NeutralButton", "NeutralButtonText"} <= names:
                ratio = contrast(colors[("NeutralButtonText", mode, high)], colors[("NeutralButton", mode, high)])
                if ratio < need:
                    errors.append(f"Text på neutral knapp: {label} ger {ratio:.2f}:1, kravet är {need}:1")
            if "LineColor" in names:
                ratio = contrast(colors[("LineColor", mode, high)], colors[("AppBackground", mode, high)])
                if ratio < 1.1:
                    errors.append(f"LineColor syns inte mot AppBackground ({label}, {ratio:.2f}:1)")
    return errors


def check_theme_names():
    """Varje `Color("Namn")` i koden ska ha en färguppsättning, annars blir färgen osynlig."""
    existing = {cs.stem for cs in ASSETS.glob("*.colorset")}
    used = set()
    for p in (ROOT / "Transkribera").rglob("*.swift"):
        used |= set(re.findall(r'Color\("([A-Za-z]+)"\)', p.read_text(encoding="utf-8")))
    return [f"Color(\"{n}\") saknar färguppsättning" for n in sorted(used - existing)]


# foregroundStyle(.orange) / foregroundColor(.orange) på text, etiketter och ikoner med text.
ORANGE = re.compile(r"foreground(?:Style|Color)\(\s*\.orange\s*\)")


def check_orange():
    return [f"{p.relative_to(ROOT)}:{n}: .orange på text, använd Color.warning"
            for p in sorted((ROOT / "Transkribera").rglob("*.swift"))
            for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1)
            if ORANGE.search(line)]


def main():
    errors = check_colorsets() + check_theme_names() + check_orange()
    if not list(ASSETS.glob("*.colorset")):
        errors.append("Hittar inga färguppsättningar")
    for e in errors:
        print("FEL:", e)
    if errors:
        sys.exit(1)
    print("Färgerna är läsbara.")


if __name__ == "__main__":
    main()
