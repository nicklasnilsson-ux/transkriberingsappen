"""Appens egna ytor har Material Design Icons (Rounded) (Nicklas 2026-11-04); macOS egna ytor
(Inställningar, titelbaren, menyerna) har SF Symbols via SystemIcon (Nicklas 2026-11-07).
Stoppar att en SF Symbol smyger in någon annanstans och att en ikon saknar bild eller licens."""
import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import material_icons  # noqa: E402
import svg_bounds  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "Transkribera"


def swift_files():
    return sorted(APP.rglob("*.swift"))


class IconTests(unittest.TestCase):
    def test_sf_symbols_only_through_system_icon(self):
        """SF Symbols hör hemma i macOS egna ytor (Nicklas 2026-11-07) och hämtas bara via SystemIcon."""
        banned = ("systemImage:", "systemName:", "systemSymbolName", "NSImage.Name")
        hits = [f"{p.name}: {b}" for p in swift_files() if p.name != "SystemIcon.swift"
                for b in banned if b in p.read_text(encoding="utf-8")]
        self.assertEqual(hits, [], "SF Symbols bara via SystemIcon (Views/SystemIcon.swift)")

    def test_system_icons_only_in_system_surfaces(self):
        """Inställningars flikar, titelbaren och menyerna har SF Symbols; appens egna ytor har Material."""
        allowed = {"SettingsView.swift", "TranscriptDetailView.swift", "PlayerBar.swift", "SystemIcon.swift"}
        users = {p.name for p in swift_files() if re.search(r"systemIcon:", p.read_text(encoding="utf-8"))}
        self.assertLessEqual(users, allowed, "SystemIcon används utanför systemytorna")
        settings = (APP / "Views/Settings/SettingsView.swift").read_text(encoding="utf-8")
        tabs = re.findall(r"\.tabItem \{([^}]*)\}", settings)
        self.assertGreaterEqual(len(tabs), 4)
        for tab in tabs:
            self.assertIn("systemIcon:", tab, f"Inställningsflik utan SF Symbol: {tab.strip()}")
        detail = (APP / "Views/Detail/TranscriptDetailView.swift").read_text(encoding="utf-8")
        for part in ("olderVersionBadge", "toolbarSearch", "editStateLabel", "editToggle", "moreMenu"):
            start = detail.index(f"private var {part}: some View")
            body = detail[start:detail.index("\n    }\n", start)]
            self.assertNotRegex(body, r"(?<![A-Za-z])icon: |Image\(icon:|Icon\(", f"{part} i titelbaren ska ha SF Symbols")
            self.assertIn("systemIcon:", body, part)
        player = (APP / "Views/Player/PlayerBar.swift").read_text(encoding="utf-8")
        menu = player[player.index("private var sizeMenu"):player.index("} label: {", player.index("private var sizeMenu"))]
        self.assertNotRegex(menu, r"(?<![A-Za-z])icon: \.", "Menyraderna i bildstorleksmenyn ska ha SF Symbols")

    def test_every_app_icon_is_used(self):
        """En ikon som ingen vy använder ska bort ur AppIcon, skriptet och resurskatalogen."""
        used = set()
        for p in swift_files():
            if p.name in ("AppIcon.swift", "SystemIcon.swift"):
                continue
            for m in re.finditer(r"(?<![A-Za-z])(?:icon:|Icon\()\s*([^\n]*)", p.read_text(encoding="utf-8")):
                depth, expr = 0, ""
                for ch in m.group(1):
                    if ch == "(":
                        depth += 1
                    if ch == ")":
                        if depth == 0:
                            break
                        depth -= 1
                    expr += ch
                used.update(re.findall(r"\.(\w+)", expr))
        self.assertEqual(sorted(set(material_icons.ICONS) - used), [], "Oanvända ikoner")

    def test_enum_matches_the_script_and_every_icon_has_an_image(self):
        enum = (APP / "Views/AppIcon.swift").read_text(encoding="utf-8")
        cases = set()
        for line in re.findall(r"^\s*case ([^\n]+)$", enum, re.M):
            cases.update(name.strip() for name in line.split(","))
        self.assertEqual(cases, set(material_icons.ICONS), "AppIcon och scripts/material_icons.py måste ha samma ikoner")
        for name in cases:
            folder = APP / f"Resources/Assets.xcassets/Icons/icon-{name}.imageset"
            contents = json.loads((folder / "Contents.json").read_text(encoding="utf-8"))
            self.assertEqual(contents["properties"]["template-rendering-intent"], "template", name)
            svg = (folder / f"{name}.svg").read_text(encoding="utf-8")
            self.assertTrue("<path" in svg or "<circle" in svg, name)
            self.assertIn('width="16"', svg, f"{name}: ikonen ska vara 16 pt")

    def test_icons_are_vectors_never_bitmaps(self):
        """Suddiga ikoner (2026-11-05): en bitmapp i 16 pt förstoras på Retina och blir suddig."""
        icons = APP / "Resources/Assets.xcassets/Icons"
        rasters = [p.name for p in icons.rglob("*") if p.suffix.lower() in (".png", ".jpg", ".jpeg", ".gif", ".tiff")]
        self.assertEqual(rasters, [], "Ikoner ska vara SVG, inte bitmappar")
        for folder in icons.glob("icon-*.imageset"):
            contents = json.loads((folder / "Contents.json").read_text(encoding="utf-8"))
            self.assertTrue(contents["properties"].get("preserves-vector-representation"), folder.name)
            files = [i["filename"] for i in contents["images"]]
            self.assertTrue(all(f.endswith(".svg") for f in files), folder.name)

    def test_icons_are_drawn_at_screen_resolution(self):
        """Ikonen får inte hämtas som vanlig Image("icon-…"): den blir bitmapp i 16 pt. All visning
        går via AppIcon.crispImage, som ritar vektorn i den skala bilden visas i."""
        src = (APP / "Views/AppIcon.swift").read_text(encoding="utf-8")
        self.assertIn("self = icon.crispImage(size: 16)", src)
        self.assertNotIn("self.init(icon.assetName)", src)
        for p in swift_files():
            if p.name == "AppIcon.swift":
                continue
            self.assertNotRegex(p.read_text(encoding="utf-8"), r'Image\(\s*"icon-|assetName', f"{p.name}: använd Image(icon:) eller Icon")

    def test_icons_stay_inside_the_grid_margin(self):
        """Handen i Inställningar (2026-11-05) gick 0–24 och nuddade texten under. Alla ikoner ska ha
        sin ritning inom 1–23 i 24-rutnätet, så att de ser lika stora ut och lämnar luft mot texten."""
        low, high = material_icons.EDGE_LIMIT
        for folder in sorted((APP / "Resources/Assets.xcassets/Icons").glob("icon-*.imageset")):
            name = folder.name[len("icon-"):-len(".imageset")]
            left, top, right, bottom = svg_bounds.bounds_in_grid((folder / f"{name}.svg").read_text(encoding="utf-8"))
            for edge, value in (("vänster", left), ("topp", top), ("höger", right), ("botten", bottom)):
                self.assertTrue(low - 0.01 <= value <= high + 0.01, f"{name}: {edge} {value:.1f} utanför {low}–{high}")

    def test_fetch_fits_an_icon_that_reaches_the_edge(self):
        raw = '<svg height="24" viewBox="0 0 24 24" width="24"><path d="M2 0h20v24H2z"/></svg>'
        left, top, right, bottom = svg_bounds.bounds_in_grid(material_icons.sized(raw))
        self.assertAlmostEqual(top, 2, places=3)
        self.assertAlmostEqual(bottom, 22, places=3)
        self.assertIn('width="16"', material_icons.sized(raw))
        inside = '<svg height="24" viewBox="0 0 24 24" width="24"><path d="M2 2h20v20H2z"/></svg>'
        self.assertIn('viewBox="0 0 24 24"', material_icons.sized(inside))

    def test_license_is_included(self):
        folder = ROOT / "third-party/material-design-icons"
        self.assertIn("Apache License", (folder / "LICENSE").read_text(encoding="utf-8"))
        self.assertIn(material_icons.COMMIT, (folder / "README.md").read_text(encoding="utf-8"))

    def test_the_app_icon_is_ours(self):
        self.assertTrue((APP / "Resources/Assets.xcassets/AppIcon.appiconset").is_dir())
        self.assertFalse(list((APP / "Resources/Assets.xcassets/AppIcon.appiconset").glob("*.svg")))


if __name__ == "__main__":
    unittest.main()
