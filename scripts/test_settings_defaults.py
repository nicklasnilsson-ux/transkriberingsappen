"""Kontroll: en av/på-inställning ska ha samma standardvärde i inställningsfönstret och
där transkriberingen läser den. Annars visar fönstret ett värde och appen använder ett annat.
Kör: python3 -m unittest discover -s scripts"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "Transkribera"
SETTINGS = APP / "Models" / "AppSettings.swift"

# @AppStorage(SettingsKey.nyckel) private var namn = true
UI = re.compile(r"@AppStorage\(SettingsKey\.(\w+)\)\s+(?:private\s+)?var\s+\w+\s*=\s*(true|false)\b")
# defaults.object(forKey: SettingsKey.nyckel) as? Bool ?? true   |   defaults.bool(forKey: SettingsKey.nyckel)
READ_OBJECT = re.compile(r"object\(forKey:\s*SettingsKey\.(\w+)\)\s+as\?\s+Bool\s+\?\?\s+(true|false)\b")
READ_BOOL = re.compile(r"\.bool\(forKey:\s*SettingsKey\.(\w+)\)")


def ui_defaults():
    found = {}
    for path in APP.rglob("*.swift"):
        for key, value in UI.findall(path.read_text(encoding="utf-8")):
            found.setdefault(key, set()).add((value == "true", path.name))
    return found


def read_defaults():
    text = SETTINGS.read_text(encoding="utf-8")
    found = {key: value == "true" for key, value in READ_OBJECT.findall(text)}
    for key in READ_BOOL.findall(text):
        found.setdefault(key, False)
    return found


class SettingsDefaultsTests(unittest.TestCase):
    def test_the_check_finds_the_settings(self):
        self.assertIn("levelVolume", ui_defaults())
        self.assertIn("levelVolume", read_defaults())

    def test_same_default_everywhere_in_the_settings_window(self):
        for key, values in ui_defaults().items():
            self.assertEqual(len({value for value, _ in values}), 1, f"{key} har olika standardvärden: {sorted(values)}")

    def test_window_and_transcription_agree(self):
        ui = ui_defaults()
        for key, value in read_defaults().items():
            if key in ui:
                shown = {v for v, _ in ui[key]}
                self.assertEqual(shown, {value}, f"{key}: fönstret visar {shown}, transkriberingen använder {value}")


if __name__ == "__main__":
    unittest.main()
