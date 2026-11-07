"""Kontroll: färgerna i Assets.xcassets ska vara läsbara.

Textfärgerna (TEXT) ska ha minst 4,5:1 mot varje bakgrund (BACKGROUNDS) i samma läge, och
varianterna för Öka kontrast minst 7:1. Texten på den neutrala (svarta) knappen ska ha samma
kontrast mot knappen. Linjerna ska synas mot bakgrunden. Varje färg som koden hämtar med
`Color("Namn")` ska finnas som färguppsättning med alla fyra varianter. Dessutom får `.orange`
inte användas på text (systemets orange ger 2,2:1 på vitt). Valt alternativ i en lista ska ha
en accentkant med minst 3:1 mot plattan och bakgrunden (check_selection). Släppytan i sidopanelen ska i vila ha
samma färg som notisrutan "Vem är intervjuare?" (NoticeBackground) och ändå synas mot kortet den
ligger i; när en fil dras över ska den skilja sig från vila (check_drop_zone, check_notice_code).
Kör: python3 scripts/check_colors.py"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Transkribera" / "Resources" / "Assets.xcassets"
LIGHT_BG, DARK_BG = (1.0, 1.0, 1.0), (0x1C / 255, 0x1C / 255, 0x21 / 255)
TEXT = ["AccentColor", "WarningColor", "SuccessColor", "TextPrimary", "TextSecondary", "TextTertiary"]
BACKGROUNDS = ["AppBackground", "SidebarBackground", "SurfaceBackground", "ChipBackground", "NoticeBackground"]
THEME = ROOT / "Transkribera" / "Views" / "Theme.swift"


def luminance(rgb):
    def lin(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def delta_e(a, b):
    """Färgskillnad i CIELAB (CIE76). Kring 2,3 är den minsta skillnad ett öga ser."""
    def lab(rgb):
        def lin(c):
            return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
        r, g, b = (lin(c) for c in rgb)
        x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        f = lambda t: t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
        return 116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))
    return sum((p - q) ** 2 for p, q in zip(lab(a), lab(b))) ** 0.5


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


SIDEBAR = ROOT / "Transkribera" / "Views" / "Sidebar" / "SidebarView.swift"
# Släppytan (Nicklas 2026-11-06, ändrat 2026-11-07): i vila samma färg som notisrutan i transkriberingen
# (NoticeBackground, svag indigo), och dra-över-läget ska skilja sig från vila. 1,10:1 är den svagaste
# ljushetsskillnad vi godtar mellan två ytor. Notisfärgen är lika ljus som kortet (ChipBackground) och
# skiljer sig bara i ton, så mot kortet mäts färgskillnad (CIELAB) i stället: minst NOTICE_VS_CARD.
DROP_REST, DROP_TARGET, DROP_CARD = "NoticeBackground", "DropZoneTargetBackground", "ChipBackground"
SURFACE_STEP = 1.10
NOTICE_VS_CARD = 2.5
# Det som står på släppytan: text ska klara textkravet, ikonerna 3:1 (WCAG för grafik).
DROP_TEXT = {DROP_REST: ["TextPrimary"], DROP_TARGET: ["TextPrimary"]}
DROP_ICON = {DROP_REST: ["TextSecondary"], DROP_TARGET: ["AccentColor"]}
# Färger som får användas i dropArea; en ny färg där måste först läggas in i kontrollen ovan.
DROP_ALLOWED = {"Color.textPrimary", "Color.textSecondary", "Color.accentColor", "Color.notice", "Color.dropZoneTarget"}


def check_drop_zone(colors=None):
    colors = colors if colors is not None else load_all()
    errors = []
    for mode in ("light", "dark"):
        for high in (False, True):
            label = f"{mode}{' hög kontrast' if high else ''}"
            key = lambda n: (n, mode, high)
            if any(key(n) not in colors for n in (DROP_REST, DROP_TARGET, DROP_CARD)):
                errors.append(f"släppytans färger saknas ({label})")
                continue
            for a, b, what in ((DROP_REST, DROP_CARD, "släppytan mot kortet"),
                               (DROP_TARGET, DROP_REST, "dra-över mot vila"),
                               (DROP_TARGET, DROP_CARD, "dra-över mot kortet")):
                ratio = contrast(colors[key(a)], colors[key(b)])
                # Dra-över mot kortet får vara lika ljust, men inte samma färg (tonen skiljer).
                if what == "dra-över mot kortet":
                    if colors[key(a)] == colors[key(b)]:
                        errors.append(f"{what}: samma färg ({label})")
                elif what == "släppytan mot kortet":
                    diff = delta_e(colors[key(a)], colors[key(b)])
                    if diff < NOTICE_VS_CARD:
                        errors.append(f"{what}: {label} ger färgskillnad {diff:.1f}, kravet är {NOTICE_VS_CARD}")
                elif ratio < SURFACE_STEP:
                    errors.append(f"{what}: {label} ger {ratio:.2f}:1, kravet är {SURFACE_STEP}:1")
            need = 7.0 if high else 4.5
            for bg, texts in DROP_TEXT.items():
                for t in texts:
                    ratio = contrast(colors[key(t)], colors[key(bg)])
                    if ratio < need:
                        errors.append(f"{t} på {bg}: {label} ger {ratio:.2f}:1, kravet är {need}:1")
            for bg, icons in DROP_ICON.items():
                for t in icons:
                    ratio = contrast(colors[key(t)], colors[key(bg)])
                    if ratio < 3.0:
                        errors.append(f"ikon {t} på {bg}: {label} ger {ratio:.2f}:1, kravet är 3:1")
    return errors


def drop_area_source():
    text = SIDEBAR.read_text(encoding="utf-8")
    start = text.find("private var dropArea: some View")
    if start < 0:
        return None
    end = text.find("\n    private var ", start + 1)
    return text[start:end if end > 0 else len(text)]


def check_drop_area_code():
    body = drop_area_source()
    if body is None:
        return ["hittar inte dropArea i SidebarView.swift"]
    errors = []
    for needed in ("Color.notice", "Color.dropZoneTarget"):
        if needed.strip() not in body:
            errors.append(f"dropArea använder inte {needed.strip()}")
    used = set(re.findall(r"Color\.[a-zA-Z]+", body))
    for extra in sorted(used - DROP_ALLOWED):
        errors.append(f"dropArea använder {extra}, som inte kontrolleras mot släppytan")
    return errors


DETAIL = ROOT / "Transkribera" / "Views" / "Detail" / "TranscriptDetailView.swift"


def notice_card_source(text=None):
    text = text if text is not None else DETAIL.read_text(encoding="utf-8")
    start = text.find("private var noticeCard: some View")
    if start < 0:
        return None
    end = text.find("\n    private ", start + 1)
    return text[start:end if end > 0 else len(text)]


def check_notice_code(detail_text=None):
    """Släppytan i vila och notisrutan ska ha samma färg (Nicklas 2026-11-07): båda använder Color.notice."""
    body = notice_card_source(detail_text)
    if body is None:
        return ["hittar inte noticeCard i TranscriptDetailView.swift"]
    errors = []
    if ".background(Color.notice" not in body:
        errors.append("noticeCard använder inte Color.notice som bakgrund")
    if re.search(r"\.background\(Color\.(?!notice\b)", body):
        errors.append("noticeCard har en annan bakgrund än Color.notice")
    drop = drop_area_source() or ""
    if not re.search(r"isDropTargeted \? Color\.dropZoneTarget : Color\.notice\b", drop):
        errors.append("dropArea ska använda Color.notice i vila och Color.dropZoneTarget vid dra-över")
    return errors


# foregroundStyle(.orange) / foregroundColor(.orange) på text, etiketter och ikoner med text.
ORANGE = re.compile(r"foreground(?:Style|Color)\(\s*\.orange\s*\)")


def check_orange():
    return [f"{p.relative_to(ROOT)}:{n}: .orange på text, använd Color.warning"
            for p in sorted((ROOT / "Transkribera").rglob("*.swift"))
            for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1)
            if ORANGE.search(line)]


# Valt alternativ i en lista (Nicklas 2026-11-07): accentkant utöver den ljusa plattan. Kanten ska ha
# minst 3:1 (WCAG 1.4.11) mot plattan innanför och mot bakgrunden utanför. Popovern har systemets
# bakgrund, som inte finns i Assets; därför ett spann av gråtoner som täcker den (ljust 0,90–1,0,
# mörkt 0,12–0,24 ≈ #1F1F1F–#3D3D3D) utöver appens egna bakgrunder.
SELECTION_NEED = 3.0
POPOVER_GRAYS = {"light": (0.90, 0.95, 1.0), "dark": (0.12, 0.18, 0.24)}
# En markerad rad med bara accentplatta (`== selection ? Color.accentColor.opacity(...)`) är felet
# som rättades; använd `.selectionHighlight(...)`.
PLATE_ONLY = re.compile(r"(==\s*selection|isSelected)\s*\?\s*Color\.accentColor\.opacity")
SELECTION_USERS = [ROOT / "Transkribera" / "Views" / "Settings" / "ModelPicker.swift"]


def selection_style():
    """(fyllnadens opacitet, kantens bredd) ur SelectionHighlight i Theme.swift."""
    src = THEME.read_text(encoding="utf-8")
    fill = re.search(r"static let fillOpacity = ([0-9.]+)", src)
    width = re.search(r"static let borderWidth: CGFloat = ([0-9.]+)", src)
    if not fill or not width:
        return None
    return float(fill.group(1)), float(width.group(1))


def check_selection(colors=None, fill=None):
    colors = colors if colors is not None else load_all()
    style = selection_style()
    if style is None:
        return ["SelectionHighlight (fillOpacity/borderWidth) saknas i Theme.swift"]
    fill = style[0] if fill is None else fill
    errors = []
    if style[1] < 1.0:
        errors.append(f"Valt alternativ: kanten är {style[1]} pt, minst 1 pt")
    for mode in ("light", "dark"):
        for high in (False, True):
            label = f"{mode}{' hög kontrast' if high else ''}"
            accent = colors.get(("AccentColor", mode, high))
            if accent is None:
                errors.append(f"AccentColor saknas ({label})")
                continue
            bgs = [(bg, colors[(bg, mode, high)]) for bg in BACKGROUNDS if (bg, mode, high) in colors]
            bgs += [(f"popover grå {g}", (g, g, g)) for g in POPOVER_GRAYS[mode]]
            for name, bg in bgs:
                plate = tuple(fill * a + (1 - fill) * b for a, b in zip(accent, bg))
                for what, other in (("bakgrunden", bg), ("plattan", plate)):
                    ratio = contrast(accent, other)
                    if ratio < SELECTION_NEED:
                        errors.append(f"Valt alternativ: kanten mot {what} på {name} ({label}) ger "
                                      f"{ratio:.2f}:1, kravet är {SELECTION_NEED}:1")
    return errors


def check_selection_code():
    errors = []
    for p in (ROOT / "Transkribera").rglob("*.swift"):
        for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            if PLATE_ONLY.search(line):
                errors.append(f"{p.relative_to(ROOT)}:{n}: markerad rad med bara accentplatta, "
                              "använd .selectionHighlight(...)")
    for p in SELECTION_USERS:
        if ".selectionHighlight(" not in p.read_text(encoding="utf-8"):
            errors.append(f"{p.relative_to(ROOT)}: valt alternativ saknar .selectionHighlight(...)")
    return errors


def main():
    errors = check_colorsets() + check_theme_names() + check_orange() + check_drop_zone() + check_drop_area_code() + check_notice_code()\
        + check_selection() + check_selection_code()
    if not list(ASSETS.glob("*.colorset")):
        errors.append("Hittar inga färguppsättningar")
    for e in errors:
        print("FEL:", e)
    if errors:
        sys.exit(1)
    print("Färgerna är läsbara.")


if __name__ == "__main__":
    main()
