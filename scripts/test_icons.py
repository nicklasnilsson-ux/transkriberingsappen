"""Ikonerna är Material Design Icons (Rounded), inte SF Symbols (Nicklas 2026-11-04).
Stoppar att en SF Symbol smyger in igen och att en ikon saknar bild eller licens."""
import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import material_icons  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "Transkribera"


def swift_files():
    return sorted(APP.rglob("*.swift"))


class IconTests(unittest.TestCase):
    def test_no_sf_symbols_anywhere(self):
        banned = ("systemImage:", "systemName:", "systemSymbolName", "NSImage.Name")
        hits = [f"{p.name}: {b}" for p in swift_files() for b in banned if b in p.read_text(encoding="utf-8")]
        self.assertEqual(hits, [], "Använd AppIcon (Image(icon:), Label(_, icon:), Icon) i stället för SF Symbols")

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

    def test_settings_tabs_use_crisp_icons(self):
        # Flikraden i Inställningar gör egna bitmappar av ikonen; en vanlig Label blev suddig (Nicklas 2026-11-04).
        settings = (APP / "Views/Settings/SettingsView.swift").read_text(encoding="utf-8")
        tabs = re.findall(r"\.tabItem \{([^}]*)\}", settings)
        self.assertGreaterEqual(len(tabs), 4)
        for tab in tabs:
            self.assertIn("CrispTabLabel(", tab, "Fliken ska använda CrispTabLabel, inte Label(_, icon:)")

    def test_license_is_included(self):
        folder = ROOT / "third-party/material-design-icons"
        self.assertIn("Apache License", (folder / "LICENSE").read_text(encoding="utf-8"))
        self.assertIn(material_icons.COMMIT, (folder / "README.md").read_text(encoding="utf-8"))

    def test_the_app_icon_is_ours(self):
        self.assertTrue((APP / "Resources/Assets.xcassets/AppIcon.appiconset").is_dir())
        self.assertFalse(list((APP / "Resources/Assets.xcassets/AppIcon.appiconset").glob("*.svg")))


if __name__ == "__main__":
    unittest.main()
