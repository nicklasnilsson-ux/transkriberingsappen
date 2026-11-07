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

    def test_theme_colors_exist(self):
        self.assertEqual(check_colors.check_theme_names(), [])

    def test_low_contrast_text_is_caught(self):
        colors = check_colors.load_all()
        key = ("TextTertiary", "light", False)
        saved = colors[key]
        try:
            colors[key] = (0.8, 0.8, 0.8)
            self.assertLess(check_colors.contrast(colors[key], colors[("AppBackground", "light", False)]), 4.5)
        finally:
            colors[key] = saved

    def test_no_orange_text(self):
        self.assertEqual(check_colors.check_orange(), [])

    def test_orange_pattern_matches(self):
        self.assertTrue(check_colors.ORANGE.search("Text(\"x\").foregroundStyle(.orange)"))
        self.assertFalse(check_colors.ORANGE.search("foregroundStyle(Color.warning)"))


if __name__ == "__main__":
    unittest.main()


class DropZoneTests(unittest.TestCase):
    """Släppytan ska synas mot kortet, och dra-över-läget mot vila (Nicklas 2026-11-06)."""

    def test_drop_zone_colors(self):
        self.assertEqual(check_colors.check_drop_zone(), [])

    def test_drop_area_uses_checked_colors(self):
        self.assertEqual(check_colors.check_drop_area_code(), [])

    def test_same_color_as_card_is_caught(self):
        # Felet som fanns före 0.9.14: ytan hade ingen egen bakgrund och syntes som kortet.
        colors = check_colors.load_all()
        for mode in ("light", "dark"):
            for high in (False, True):
                colors[(check_colors.DROP_REST, mode, high)] = colors[(check_colors.DROP_CARD, mode, high)]
        self.assertTrue(any("släppytan mot kortet" in e for e in check_colors.check_drop_zone(colors)))

    def test_drop_zone_matches_notice_card(self):
        self.assertEqual(check_colors.check_notice_code(), [])

    def test_old_tint_on_notice_card_is_caught(self):
        # Före 2026-11-07 tonades rutan med accentfärg direkt, och släppytan hade en egen färg.
        text = check_colors.DETAIL.read_text(encoding="utf-8")
        old = text.replace(".background(Color.notice,", ".background(Color.accentColor.opacity(0.08),")
        self.assertNotEqual(old, text)
        self.assertTrue(check_colors.check_notice_code(old))

    def test_target_equal_to_rest_is_caught(self):
        colors = check_colors.load_all()
        key = (check_colors.DROP_TARGET, "dark", False)
        colors[key] = colors[(check_colors.DROP_REST, "dark", False)]
        self.assertTrue(any("dra-över mot vila" in e for e in check_colors.check_drop_zone(colors)))


class SelectionTests(unittest.TestCase):
    """Valt alternativ: accentkant med minst 3:1 mot plattan och bakgrunden (Nicklas 2026-11-07)."""

    def test_selection_border_contrast(self):
        self.assertEqual(check_colors.check_selection(), [])

    def test_selection_code(self):
        self.assertEqual(check_colors.check_selection_code(), [])

    def test_stronger_plate_would_fail(self):
        # Plattan i 0.9.19 (0,15) ger 2,97:1 mot kanten på mörkast tänkbara ljusa popover-grå (0,24).
        self.assertTrue(check_colors.check_selection(fill=0.15))

    def test_plate_only_pattern(self):
        old = "model == selection ? Color.accentColor.opacity(0.15) : .clear,"
        self.assertTrue(check_colors.PLATE_ONLY.search(old))
        self.assertFalse(check_colors.PLATE_ONLY.search(".selectionHighlight(model == selection)"))
