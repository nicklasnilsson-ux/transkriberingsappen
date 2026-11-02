"""Kör accentkontrollen som en del av scripttesterna: python3 -m unittest discover -s scripts"""
import unittest

import check_accent


class AccentTests(unittest.TestCase):
    def test_accent_is_wired_and_matches_icon(self):
        self.assertEqual(check_accent.check(), [])

    def test_reader_finds_icon_background(self):
        icon = check_accent.ASSETS / "AppIcon.appiconset" / "icon_512x512@2x.png"
        self.assertEqual(check_accent.read_png_pixel(icon, 5, 5)[3], 0)  # hörnet är genomskinligt


if __name__ == "__main__":
    unittest.main()
