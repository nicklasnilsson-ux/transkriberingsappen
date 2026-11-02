"""Kontroll: Testlabbet är ett utvecklingsverktyg och ska inte synas för vanliga användare.
Det får inte finnas som menyval eller synlig knapp, bara via den dolda genvägen.
Kör: python3 -m unittest discover -s scripts"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = (ROOT / "Transkribera" / "App" / "TranskriberaApp.swift").read_text(encoding="utf-8")


class TestLabHiddenTests(unittest.TestCase):
    def test_no_menu_entry_or_visible_label(self):
        self.assertNotIn('Button("Testlabb', APP)
        commands = APP[APP.index(".commands {"):APP.index("Window(")]
        self.assertNotIn("TestLab", commands, "Testlabbet får inte ligga i en meny")

    def test_window_opens_only_through_hidden_shortcut(self):
        self.assertIn("struct TestLabShortcut", APP)
        self.assertRegex(APP, r'\.keyboardShortcut\("t", modifiers: \[\.command, \.option, \.shift\]\)')
        self.assertIn(".opacity(0)", APP)
        self.assertIn(".accessibilityHidden(true)", APP)
        self.assertEqual(len(re.findall(r"openWindow\(id:", APP)), 1)


if __name__ == "__main__":
    unittest.main()
