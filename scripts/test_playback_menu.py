"""Kontroll: menyn Uppspelning har sina kortkommandon (Nicklas 2026-11-07), och inget kortkommando
i appens menyer används två gånger. Kör: python3 -m unittest discover -s scripts"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "Transkribera"
MAIN = APP / "App" / "TranskriberaApp.swift"

# Button("Titel") { ... } följt (inom några rader) av .keyboardShortcut(tangent[, modifiers: ...])
SHORTCUT = re.compile(r'\.keyboardShortcut\(\s*("(?:[^"\\]|\\.)*"|\.\w+)\s*(?:,\s*modifiers:\s*(\[[^\]]*\]|\.\w+))?\s*\)')
BUTTON = re.compile(r'Button\("([^"]+)"\)')


def normalize(key, modifiers):
    if key in (".defaultAction", ".cancelAction"):
        return None
    if modifiers is None:
        mods = {"command"}
    else:
        mods = set(re.findall(r"\.(\w+)", modifiers))
    return (key.strip('"').lower(), tuple(sorted(mods)))


def shortcuts(path):
    """(titel, (tangent, modifierare)) för varje knapp med kortkommando i filen."""
    text = path.read_text(encoding="utf-8")
    found = []
    for match in SHORTCUT.finditer(text):
        combo = normalize(match.group(1), match.group(2))
        if combo is None:
            continue
        before = text[max(0, match.start() - 400):match.start()]
        titles = BUTTON.findall(before)
        found.append((titles[-1] if titles else "?", combo))
    return found


class PlaybackMenuTests(unittest.TestCase):
    def test_playback_menu_has_its_shortcuts(self):
        text = MAIN.read_text(encoding="utf-8")
        self.assertIn('CommandMenu("Uppspelning")', text)
        found = dict(shortcuts(MAIN))
        self.assertEqual(found.get("Spela/Pausa"), ("p", ("command", "option")))
        self.assertEqual(found.get("Snabbare"), (".rightarrow", ("command", "option")))
        self.assertEqual(found.get("Långsammare"), (".leftarrow", ("command", "option")))
        self.assertEqual(found.get("Normal hastighet"), ("0", ("command", "option")))

    def test_no_shortcut_is_used_twice(self):
        seen = {}
        for path in sorted(APP.rglob("*.swift")):
            for title, combo in shortcuts(path):
                seen.setdefault(combo, []).append(f"{path.name}: {title}")
        # Escape används av flera ark för att stänga; det är avsiktligt och gäller bara i arket.
        doubles = {combo: where for combo, where in seen.items() if len(where) > 1 and combo[0] != ".escape"}
        self.assertEqual(doubles, {}, f"Samma kortkommando på flera ställen: {doubles}")


if __name__ == "__main__":
    unittest.main()
