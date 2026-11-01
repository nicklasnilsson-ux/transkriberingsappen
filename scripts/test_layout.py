"""Kontroll av grundstrukturen i fönstret: hela fönstret tar emot släppta filer (en enda
släppyta, på roten) och lägesväxlaren sitter i verktygsfältet.
Kör: python3 -m unittest discover -s scripts"""
import unittest
from pathlib import Path

VIEWS = Path(__file__).resolve().parent.parent / "Transkribera" / "Views"


class LayoutTests(unittest.TestCase):
    def test_only_the_root_accepts_dropped_files(self):
        users = [p.name for p in VIEWS.rglob("*.swift") if ".dropDestination(" in p.read_text(encoding="utf-8")]
        self.assertEqual(users, ["ContentView.swift"], f"Släppyta utanför roten: {users}")

    def test_mode_switcher_is_in_the_toolbar(self):
        text = (VIEWS / "ContentView.swift").read_text(encoding="utf-8")
        self.assertIn("ToolbarItem(placement: .principal)", text)
        self.assertIn(".pickerStyle(.segmented)", text)

    def test_sidebar_groups_come_from_the_tested_core_function(self):
        text = (VIEWS / "Sidebar" / "SidebarView.swift").read_text(encoding="utf-8")
        self.assertIn("SidebarGroup.group(", text)


class MeetingModeTests(unittest.TestCase):
    def test_no_live_text_during_recording(self):
        # Beslut: möte = inspelningsstatus, texten skapas först när inspelningen stoppas.
        for name in ("Home/RecordingPanel.swift", "Home/FileModeEmptyView.swift"):
            text = (VIEWS / name).read_text(encoding="utf-8")
            self.assertNotIn("liveText", text, name)

    def test_microphone_toggle_lives_in_the_inspector(self):
        inspector = (VIEWS / "Home" / "MeetingInspector.swift").read_text(encoding="utf-8")
        self.assertIn("Spela även in min mikrofon", inspector)
        self.assertIn(".inspector(", (VIEWS / "Home" / "FileModeEmptyView.swift").read_text(encoding="utf-8"))


class MinimumOSTests(unittest.TestCase):
    def test_no_macos_15_only_api(self):
        # Lägsta version är macOS 14 (project.yml). Dessa finns först i macOS 15.
        banned = ["onScrollGeometryChange", "toolbar(removing:", "searchFocused(", "ContainerBackgroundPlacement"]
        hits = [f"{p.name}: {b}" for p in VIEWS.parent.rglob("*.swift")
                for b in banned if b in p.read_text(encoding="utf-8")]
        self.assertEqual(hits, [], f"API som kräver macOS 15: {hits}")


class EditModeTests(unittest.TestCase):
    """Redigeringsläget får inte flytta texten, ska synas tydligt och gå att stänga med Esc."""

    DETAIL = VIEWS / "Detail"

    def test_entering_edit_mode_inserts_nothing_above_the_text(self):
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        start = text.index("private var noticeCard")
        block = text[start:text.index("// 7.", start)]
        self.assertNotIn("isEditing", block, "Kortet ovanför texten får inte bero på redigeringsläget (layouten hoppar)")
        roles = text[text.index("private var showsRolesBanner"):][:200]
        self.assertNotIn("!isEditing", roles, "Rollbannern får inte försvinna när redigeringsläget slås på (layouten hoppar)")

    def test_view_and_edit_text_share_the_same_surface(self):
        for name in ("ParagraphRow.swift", "SegmentRow.swift"):
            self.assertIn("EditSurface(isEditing: false)", (self.DETAIL / name).read_text(encoding="utf-8"), name)
        row = (self.DETAIL / "SegmentRow.swift").read_text(encoding="utf-8")
        self.assertIn("EditSurface(isEditing: isEditable", row)
        self.assertIn(".lineSpacing(lineSpacing)", row, "Fältet ska ha samma radavstånd som visningen")

    def test_edit_mode_is_labelled_and_closes_with_escape(self):
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        for needle in ('"Klar"', "editingPill", ".onExitCommand", ".keyboardShortcut(.escape"):
            self.assertIn(needle, text)

    def test_escape_shortcut_only_exists_while_editing(self):
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        i = text.index(".keyboardShortcut(.escape")
        self.assertIn("if isEditing", text[i - 200:i], "Esc får inte slå PÅ redigeringsläget")


class TimecodeTests(unittest.TestCase):
    def test_paragraphs_and_rows_use_the_same_timecode_button(self):
        for name in ("ParagraphRow.swift", "SegmentRow.swift"):
            self.assertIn("TimecodeButton(", (VIEWS / "Detail" / name).read_text(encoding="utf-8"), name)

    def test_play_icon_space_is_always_reserved(self):
        text = (VIEWS / "Detail" / "SegmentRow.swift").read_text(encoding="utf-8")
        self.assertIn(".opacity(hovering ? 1 : 0)", text, "Ikonen ska tonas, inte läggas till, så att inget flyttar sig")


class RetranscribeTests(unittest.TestCase):
    def test_every_retranscribe_call_carries_a_confirmation(self):
        calls = []
        for path in (VIEWS.parent).rglob("*.swift"):
            for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if ".retranscribe(" in line and "confirmation:" not in line:
                    calls.append(f"{path.name}:{n}")
        self.assertEqual(calls, [], f"Omtagning utan bekräftelse: {calls}")

    def test_the_confirmation_dialog_is_used_where_text_would_be_replaced(self):
        for name in ("Detail/TranscriptDetailView.swift", "Sidebar/SidebarView.swift"):
            text = (VIEWS / name).read_text(encoding="utf-8")
            self.assertIn("RetranscribeConfirmation.dialogMessage", text, name)

    def test_collapsed_bar_uses_the_tested_thresholds(self):
        text = (VIEWS / "Detail" / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        self.assertIn("TitleCardCollapse.isCollapsed(", text)
        self.assertIn("accessibilityReduceMotion", text)


if __name__ == "__main__":
    unittest.main()
