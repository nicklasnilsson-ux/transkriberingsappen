"""Kör färgkontrollen som en del av scripttesterna: python3 -m unittest discover -s scripts"""
import unittest

import check_colors


class ColorTests(unittest.TestCase):
    def test_contrast_math(self):
        self.assertAlmostEqual(check_colors.contrast((0, 0, 0), (1, 1, 1)), 21.0, places=1)

    def test_old_accent_would_fail(self):
        # Den gamla accentfärgen #4F7AEB gav 3,95:1 mot vitt.
        rgb = (0x4F / 255, 0x7A / 255, 0xEB / 255)
        self.assertLess(check_colors.contrast(rgb, check_colors.LIGHT_BG), 4.5)

    def test_system_orange_would_fail(self):
        self.assertLess(check_colors.contrast((1.0, 0.584, 0.0), check_colors.LIGHT_BG), 4.5)

    def test_color_sets_are_readable(self):
        self.assertEqual(check_colors.check_colorsets(), [])

    def test_no_orange_text(self):
        self.assertEqual(check_colors.check_orange(), [])

    def test_orange_pattern_matches(self):
        self.assertTrue(check_colors.ORANGE.search("Text(\"x\").foregroundStyle(.orange)"))
        self.assertFalse(check_colors.ORANGE.search("foregroundStyle(Color.warning)"))


if __name__ == "__main__":
    unittest.main()
