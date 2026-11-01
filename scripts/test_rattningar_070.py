"""Kontroll: det som saknades i 0.7.0 (skärmdump från Nicklas) finns i koden.
Varje test motsvarar ett fel. Kör: python3 -m unittest discover -s scripts"""
import re
import unittest
from pathlib import Path

V = Path(__file__).resolve().parent.parent / "Transkribera"
sidebar = (V / "Views/Sidebar/SidebarView.swift").read_text(encoding="utf-8")
detail = (V / "Views/Detail/TranscriptDetailView.swift").read_text(encoding="utf-8")
queue = (V / "Services/TranscriptionQueue.swift").read_text(encoding="utf-8")
body = sidebar[sidebar.index("var body: some View"):sidebar.index(".navigationSplitViewColumnWidth")]


class SidebarOrderTests(unittest.TestCase):
    def test_order_settings_dropzone_heading_search_list(self):
        order = [body.index(x) for x in ("settingsButton", "dropArea", "listHeader", "list")]
        self.assertEqual(order, sorted(order))

    def test_dropzone_has_choose_files_and_highlight(self):
        self.assertIn('Button("Välj filer…")', sidebar)
        self.assertIn("isDropTargeted", sidebar)

    def test_search_is_under_the_heading(self):
        header = sidebar[sidebar.index("var listHeader"):]
        self.assertLess(header.index("Transkriberingar ("), header.index("TextField"))

    def test_no_model_footer_at_the_bottom(self):
        self.assertNotIn("modelFooter", sidebar)


class FinishedTranscriptionSettingsTests(unittest.TestCase):
    def test_chips_open_rerun_settings(self):
        self.assertIn("RerunSettingsPopover", detail)
        self.assertNotIn("infoChip(", detail)  # chipsen var tidigare bara text

    def test_overrides_reach_the_queue_and_are_consumed_once(self):
        self.assertIn("overrides: overrides", detail)
        self.assertIn("overridesByID.removeValue(forKey", queue)

    def test_overrides_do_not_touch_user_defaults(self):
        popover = (V / "Views/Detail/RerunSettingsPopover.swift").read_text(encoding="utf-8")
        # Bara läsning av standardvärden; skrivningar går till overrides.
        self.assertNotRegex(popover, r"\$(defaultModel|defaultLanguage|defaultIdentify|defaultSpeakers)")


class EmptyViewTests(unittest.TestCase):
    def test_settings_row_sits_at_the_top_of_the_empty_view(self):
        empty = (V / "Views/Home/FileModeEmptyView.swift").read_text(encoding="utf-8")
        view = empty[empty.index("struct FileModeEmptyView"):empty.index("struct NextTranscriptionChips")]
        self.assertLess(view.index("NextTranscriptionChips()"), view.index("ContentUnavailableView"))
        self.assertRegex(view, r"alignment: \.top\)\s*\n\s*\.navigationTitle")


class CollapseAndPlayerTests(unittest.TestCase):
    def test_scroll_is_read_from_the_real_scroll_view(self):
        # GeometryReader ensam rapporterade inte under skrollning (0.7.1 fällde inte ihop).
        self.assertIn("ScrollOffsetObserver {", detail)
        probe = (V / "Views/Detail/ScrollOffsetObserver.swift").read_text(encoding="utf-8")
        self.assertIn("boundsDidChangeNotification", probe)
        self.assertIn("postsBoundsChangedNotifications = true", probe)

    def test_scroll_offset_measured_on_whole_content(self):
        self.assertRegex(detail, r"\.background\(GeometryReader[\s\S]{0,200}ScrollOffsetKey")
        self.assertNotIn("scrollOffsetProbe", detail)

    def test_mini_player_in_collapsed_bar_with_three_sizes(self):
        bar = detail[detail.index("func collapsedBar"):detail.index("func miniPlayer")]
        self.assertIn("miniPlayer(", bar)
        self.assertIn("MiniPlayerSize.allCases", detail)


if __name__ == "__main__":
    unittest.main()
