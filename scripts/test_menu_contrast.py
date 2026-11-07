"""Kontroll: texter i menyer och sidopanel som macOS annars ritar ljusgrå (för låg kontrast).

macOS ritar rubriker i menyer (inline-`Picker`, `Section("…")`, `NSMenuItem.sectionHeader`) och
`Text` som står ensam i en `Menu` i ljusgrått. I Nicklas skärmbild 2026-11-07 hade rubriken
Bildstorlek 1,9:1 mot menyn; kravet för liten text är 4,5:1. Rubriker och förklaringar i menyer ritas
därför av appen (`AppMenu`, i TextSecondary), och sidopanelens rubriker har egen text i TextSecondary.
Kör: python3 -m unittest discover -s scripts"""
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_colors  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "Transkribera"
# Formulären i Inställningar och Testlabbet ritar sina rubriker med normal kontrast.
FORMS = {"Settings", "TestLab"}
# Menyns bakgrund, uppmätt i Nicklas skärmbilder 2026-11-07 (macOS 26): ljust (236,236,236),
# mörkt (50,50,50). Rubriken i mörkt läge mättes till 6,24:1 i samma skärmbild.
MENU_BG = {"light": (236 / 255,) * 3, "dark": (0x32 / 255,) * 3}


def swift_files():
    return sorted(APP.rglob("*.swift"))


def menu_bodies(text):
    """Innehållet i varje `Menu {` … (fram till motsvarande `}`)."""
    for match in re.finditer(r"\bMenu\s*(?:\([^)]*\))?\s*\{", text):
        depth, i = 1, match.end()
        while depth and i < len(text):
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            i += 1
        yield text[match.end():i - 1]


class MenuContrastTests(unittest.TestCase):
    def test_no_system_drawn_headers(self):
        found = []
        for path in swift_files():
            text = path.read_text(encoding="utf-8")
            rel = path.relative_to(APP)
            if ".pickerStyle(.inline)" in text:
                found.append(f"{rel}: .pickerStyle(.inline) (rubriken blir ljusgrå i en meny)")
            if "NSMenuItem.sectionHeader" in text:
                found.append(f"{rel}: NSMenuItem.sectionHeader (ljusgrå rubrik, använd AppMenu)")
            if not FORMS & set(rel.parts) and re.search(r'Section\(\s*"', text):
                found.append(f'{rel}: Section("…") ritar en ljusgrå rubrik; använd header: {{ Text … }}')
        self.assertEqual(found, [])

    def test_no_lone_text_in_menus(self):
        found = []
        for path in swift_files():
            for body in menu_bodies(path.read_text(encoding="utf-8")):
                for line in body.splitlines():
                    if re.match(r"\s*Text\(", line):
                        found.append(f"{path.name}: {line.strip()[:70]}")
        self.assertEqual(found, [], "Text i en meny ritas ljusgrå; använd AppMenu och .note")

    def test_the_check_finds_menus(self):
        text = (APP / "Views/Detail/TranscriptDetailView.swift").read_text(encoding="utf-8")
        self.assertTrue(any("Kopiera text" in body for body in menu_bodies(text)))

    def test_app_menu_draws_headers_in_secondary_text(self):
        src = (APP / "Views/AppMenu.swift").read_text(encoding="utf-8")
        self.assertIn('textColorName = "TextSecondary"', src)
        self.assertIn("NSColor(named: textColorName)", src)
        colors = check_colors.load_all()
        for mode, bg in MENU_BG.items():
            for high in (False, True):
                ratio = check_colors.contrast(colors[("TextSecondary", mode, high)], bg)
                self.assertGreaterEqual(ratio, 4.5, f"TextSecondary mot menyn ({mode}, hög kontrast {high}): {ratio:.2f}")

    def test_menus_with_headers_use_app_menu(self):
        bar = (APP / "Views/Player/PlayerBar.swift").read_text(encoding="utf-8")
        self.assertIn('.header("Bildstorlek")', bar)
        speed = (APP / "Views/Player/PlaybackSpeedButton.swift").read_text(encoding="utf-8")
        self.assertIn('.header("Uppspelningshastighet")', speed)
        detail = (APP / "Views/Detail/TranscriptDetailView.swift").read_text(encoding="utf-8")
        self.assertIn('.note("De \\(VersionHistory.capacity) senaste versionerna sparas', detail)


    def test_text_fields_have_readable_placeholders(self):
        """macOS ritar platshållare ljusgrått. Varje TextField tar sin platshållare från
        `.prompt(…)` (TextSecondary). Undantag: fälten i systemets .alert, som macOS ritar själv."""
        alert_fields = {("TranscriptDetailView.swift", 'TextField("Namn", text: $newSpeakerName)'),
                        ("TranscriptDetailView.swift", 'TextField("Namn", text: $newSpeakerDraft)')}
        found, seen = [], 0
        for path in swift_files():
            for line in path.read_text(encoding="utf-8").splitlines():
                if not re.search(r'\bTextField\(\s*"', line):
                    continue
                seen += 1
                code = line.strip()
                if (path.name, code) in alert_fields:
                    continue
                if "prompt: .prompt(" not in code:
                    found.append(f"{path.name}: {code[:80]}")
        self.assertGreaterEqual(seen, 8, "Kontrollen hittar inte textfälten")
        self.assertEqual(found, [], "Platshållaren blir ljusgrå; ange prompt: .prompt(\"…\")")
        theme = (APP / "Views/Theme.swift").read_text(encoding="utf-8")
        self.assertIn("static func prompt(_ text: String) -> Text", theme)
        self.assertIn("Text(text).foregroundStyle(Color.textSecondary)", theme)


if __name__ == "__main__":
    unittest.main()
