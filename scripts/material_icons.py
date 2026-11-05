#!/usr/bin/env python3
"""Hämtar appens ikoner från Material Design Icons (stilen Rounded) och lägger dem som ikonuppsättningar
i resurskatalogen. Källan är fastlåst till en commit, så att en ny hämtning ger exakt samma filer.

  material_icons.py fetch    Hämtar ikonerna och skriver ikonuppsättningar + licensfil.
  material_icons.py list     Skriver ut ikonerna (namn i appen -> namn hos Material).

Ikonerna är Apache 2.0 (Google). Licensen ligger i third-party/material-design-icons/LICENSE.
Namnen här är samma som i `AppIcon` (Transkribera/Views/AppIcon.swift); scripts/test_icons.py
kontrollerar att de hänger ihop."""
import json
import re
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import svg_bounds  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Transkribera/Resources/Assets.xcassets/Icons"
THIRD_PARTY = ROOT / "third-party/material-design-icons"
COMMIT = "10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7"
BASE = f"https://raw.githubusercontent.com/google/material-design-icons/{COMMIT}"
CATEGORIES = ["action", "alert", "av", "communication", "content", "device", "editor", "file", "hardware",
              "image", "maps", "navigation", "notification", "places", "social", "toggle"]
STYLE = "materialiconsround"
# Ikonens bredd och höjd i punkter när den ritas utan egen storlek (menyer, knappar).
POINTS = 16
# Ritytan i 24-rutnätet. Material lämnar 2 enheter runt om; en ikon som går längre ut än 1 enhet från
# kanten (pan_tool går 0–24) ser större ut än de andra och nuddar texten under, så den skalas in.
LIVE_AREA = (2, 22)
EDGE_LIMIT = (1, 23)

# namn i appen -> namn hos Material
ICONS = {
    "check": "check",
    "checkCircle": "check_circle",
    "cancel": "cancel",
    "chevronDown": "keyboard_arrow_down",
    "chevronUp": "keyboard_arrow_up",
    "unfold": "unfold_more",
    "circle": "radio_button_unchecked",
    "clock": "schedule",
    "copy": "content_copy",
    "chip": "developer_board",
    "download": "file_download",
    "downloadCircle": "arrow_circle_down",
    "edit": "edit",
    "fullscreen": "fullscreen",
    "fullscreenExit": "fullscreen_exit",
    "group": "group",
    "hand": "pan_tool",
    "history": "history",
    "info": "info",
    "lightbulb": "lightbulb",
    "memory": "memory",
    "more": "more_horiz",
    "movie": "movie",
    "openInFull": "open_in_full",
    "openInNew": "open_in_new",
    "closeFullscreen": "close_fullscreen",
    "pause": "pause",
    "personQuestion": "contact_support",
    "play": "play_arrow",
    "playCircle": "play_circle",
    "record": "fiber_manual_record",
    "refresh": "refresh",
    "search": "search",
    "share": "ios_share",
    "sync": "sync",
    "tune": "tune",
    "visibility": "visibility",
    "visibilityOff": "visibility_off",
    "warning": "warning",
    "waveform": "graphic_eq",
}


def fetch(url: str) -> bytes | None:
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            return response.read()
    except Exception:
        return None


def svg_for(material: str) -> tuple[str, str]:
    for category in CATEGORIES:
        data = fetch(f"{BASE}/src/{category}/{material}/{STYLE}/24px.svg")
        if data:
            return category, data.decode("utf-8")
    raise SystemExit(f"Hittar inte {material} i {STYLE}")


def fitted(svg: str) -> str:
    """Skalar in en ikon som går ut mot kanten, genom att göra viewBox större runt mitten (12, 12),
    så att den största sidan ryms i ritytan. Ikoner inom gränsen lämnas som de är."""
    left, top, right, bottom = svg_bounds.bounds_in_grid(svg)
    low, high = EDGE_LIMIT
    if left >= low and top >= low and right <= high and bottom <= high:
        return svg
    reach = max(12 - left, 12 - top, right - 12, bottom - 12)
    size = 24 * reach / (LIVE_AREA[1] - 12)
    origin = 12 - size / 2
    box = f"{origin:g} {origin:g} {size:g} {size:g}"
    return re.sub(r'viewBox="[^"]+"', f'viewBox="{box}"', svg, count=1)


def sized(svg: str) -> str:
    """Samma ritning, inskalad vid behov (se fitted), med bredd och höjd i punkter, så att den får rätt
    storlek där ingen anges."""
    svg = fitted(svg)
    svg = re.sub(r'\sheight="24"', f' height="{POINTS}"', svg, count=1)
    svg = re.sub(r'\swidth="24"', f' width="{POINTS}"', svg, count=1)
    return svg


def write_asset(name: str, svg: str) -> None:
    folder = ASSETS / f"icon-{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f"{name}.svg").write_text(sized(svg), encoding="utf-8")
    contents = {
        "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
    }
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else "list"
    if command == "list":
        for name, material in ICONS.items():
            print(f"{name} -> {material}")
        return
    if command != "fetch":
        raise SystemExit(__doc__)
    ASSETS.mkdir(parents=True, exist_ok=True)
    (ASSETS / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    for name, material in ICONS.items():
        category, svg = svg_for(material)
        write_asset(name, svg)
        print(f"{name}: {category}/{material}")
    THIRD_PARTY.mkdir(parents=True, exist_ok=True)
    license_text = fetch(f"{BASE}/LICENSE")
    if not license_text:
        raise SystemExit("Hittar inte LICENSE")
    (THIRD_PARTY / "LICENSE").write_bytes(license_text)
    (THIRD_PARTY / "README.md").write_text(
        "# Material Design Icons\n\n"
        "Ikonerna i appen (stilen Rounded) kommer från https://github.com/google/material-design-icons,\n"
        f"commit `{COMMIT}`, och används under Apache License 2.0 (se LICENSE här).\n"
        "Appikonen är egen och ingår inte. Hämta om dem med `python3 scripts/material_icons.py fetch`.\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
