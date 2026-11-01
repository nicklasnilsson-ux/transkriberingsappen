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


class RerunButtonTests(unittest.TestCase):
    def test_button_is_emphasized_only_when_settings_changed(self):
        self.assertIn("RerunButtonStyle(isEmphasized: rerunSettingsChanged)", detail)
        self.assertIn("RerunChange.isChanged(", detail)


class MultiSelectTests(unittest.TestCase):
    def test_list_supports_multiple_selection_and_click_to_deselect(self):
        self.assertIn("List(selection: listSelection)", sidebar)
        self.assertIn("toggleOff(", sidebar)
        self.assertIn("leftMouseDown", sidebar)  # vad som var valt innan klicket

    def test_detail_shows_multi_selection_view(self):
        content = (V / "Views/ContentView.swift").read_text(encoding="utf-8")
        self.assertIn("MultiSelectionView(", content)

    def test_bulk_actions_ask_first_and_say_how_many(self):
        view = (V / "Views/Home/MultiSelectionView.swift").read_text(encoding="utf-8")
        self.assertIn("RetranscribeConfirmation(replacingText", view)
        self.assertIn("DeleteConfirmation(count:", view)
        self.assertIn("BulkRetranscribe.message(count: count)", view)
        self.assertIn("DeleteConfirmation.message(count: count)", view)
        # Köns flerfunktioner kan inte anropas utan bekräftelsetypen.
        self.assertRegex(queue, r"func delete\(_ transcripts: \[Transcript\], confirmation: DeleteConfirmation\)")
        self.assertRegex(queue, r"func retranscribe\(_ transcripts: \[Transcript\], confirmation: RetranscribeConfirmation\)")

    def test_every_bulk_call_passes_a_confirmation(self):
        for path in V.rglob("*.swift"):
            text = path.read_text(encoding="utf-8")
            for m in re.finditer(r"queue\.(retranscribe|delete)\(\s*(chosen|transcripts)", text):
                tail = text[m.start():m.start() + 120]
                self.assertIn("confirmation:", tail, f"{path.name}: {tail}")


if __name__ == "__main__":
    unittest.main()
