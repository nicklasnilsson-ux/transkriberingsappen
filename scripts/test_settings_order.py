"""Kontroll: avsnitten i fliken Transkribering ligger i den godkända ordningen (layoutskissen).
Kör: python3 -m unittest discover -s scripts"""
import re
import unittest
from pathlib import Path

SETTINGS = Path(__file__).resolve().parent.parent / "Transkribera" / "Views" / "Settings" / "SettingsView.swift"
ORDER = ["Språk", "Talare", "Ordlista", "Ordträff", "Tidsstämplar", "Mötesinspelning", "Experiment"]


class SettingsOrderTests(unittest.TestCase):
    def test_sections_in_the_approved_order(self):
        text = SETTINGS.read_text(encoding="utf-8")
        start = text.index("private struct TranscriptionSettingsView")
        end = text.index("private struct PrivacySettingsView")
        headers = re.findall(r"\} header: \{\s*Text\(\"([^\"]+)\"\)", text[start:end])
        self.assertEqual(headers, ORDER)

    def test_no_cancel_button_in_settings(self):
        # Ändringar sparas direkt. (Arket "Vilken modell ska jag välja?" har en egen Klar-knapp.)
        self.assertNotIn('Button("Avbryt"', SETTINGS.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
