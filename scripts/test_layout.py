"""Kontroll av grundstrukturen i fönstret: hela fönstret tar emot släppta filer (en enda
släppyta, på roten) och lägesväxlaren sitter i verktygsfältet.
Kör: python3 -m unittest discover -s scripts"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VIEWS = ROOT / "Transkribera" / "Views"


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

    def test_edit_surface_takes_no_space_in_the_layout(self):
        # Fältytan ritas utanför texten. Positiv padding eller en ram på varje segment gjorde att
        # varje textrad växte i höjd när man gick in i redigeringsläget.
        row = (self.DETAIL / "SegmentRow.swift").read_text(encoding="utf-8")
        start = row.index("struct EditSurface")
        surface = row[start:row.index("/// Aktivt stycke", start)]
        self.assertNotIn(".padding(.horizontal, 6)", surface)
        for line in surface.splitlines():
            if ".padding(" in line:
                self.assertIn("-", line, f"Positiv padding i EditSurface: {line.strip()}")
        self.assertIn(".lineSpacing(lineSpacing)", row, "Fältet ska ha samma radavstånd som visningen")
        editor = row[row.index("struct SegmentEditor"):start]
        self.assertNotIn("EditSurface", editor, "Ytan läggs på raden eller stycket, inte på varje segment")

    def test_the_surface_is_added_once_per_row_or_paragraph(self):
        self.assertIn(".modifier(EditSurface())", (self.DETAIL / "ParagraphRow.swift").read_text(encoding="utf-8"))
        self.assertIn(".modifier(EditSurface())", (self.DETAIL / "SegmentRow.swift").read_text(encoding="utf-8"))

    def test_edit_mode_is_labelled_and_closes_with_escape(self):
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        for needle in ('"Klar"', "editStateLabel", ".onExitCommand", ".keyboardShortcut(.escape"):
            self.assertIn(needle, text)

    def test_edit_state_label_sits_next_to_the_edit_button_not_on_the_title_row(self):
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        start = text.index("private func searchAndEditRow")
        row = text[start:text.index("\n    }\n", start)]
        # Nicklas skiss 2026-11-02: Sök i texten, Redigera/Klar, och texten om redigeringen sist,
        # så att ingenting annat flyttar sig när den visas.
        self.assertLess(row.index("searchButton("), row.index("editToggle"))
        self.assertLess(row.index("editToggle"), row.index("editStateLabel"))
        title_row = text[text.index("private var titleRow"):text.index("private var layoutPicker")]
        self.assertNotIn("isEditing", title_row, "Titelraden ändras inte av redigeringsläget (layouten hoppar)")

    def test_title_card_follows_the_sketch(self):
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        card = text[text.index("private var titleCard"):text.index("private var titleRow")]
        tools = ["speakersMenu", "anonymizeToggle", "layoutPicker", "copyButton", "exportMenu()", "Divider()", "searchAndEditRow("]
        positions = [card.index(t) for t in tools]
        self.assertEqual(positions, sorted(positions), "Ordningen i titelkortet följer skissen")
        self.assertNotIn("interviewerPill", text, "Intervjuaren väljs under Talare, inget märke efter titeln")
        bar = text[text.index("func collapsedBar"):text.index("func miniPlayer")]
        self.assertIn("searchAndEditRow(scrollProxy: proxy)", bar, "Samma Sök/Redigera-rad i den hopfällda raden")
        for tool in ("anonymizeToggle", "copyButton", "exportMenu()", "speakersMenu"):
            self.assertNotIn(tool, bar, f"{tool} finns bara i titelkortet")
        self.assertLess(bar.index("searchAndEditRow"), bar.index("miniPlayer("), "Titel och knappar till vänster, spelaren till höger")

    def test_on_states_are_filled_and_keep_their_size(self):
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        self.assertIn(".modifier(OnStateButtonStyle(isOn: isEditing))", text)
        self.assertIn(".modifier(OnStateButtonStyle(isOn: anonymize))", text)
        export = text[text.index("private func exportMenu"):text.index("private var playerCard")]
        self.assertNotIn("borderedProminent", export, "Fylld betyder att ett läge är på; Exportera är ingen växel")

    def test_escape_shortcut_only_exists_while_editing(self):
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        i = text.index(".keyboardShortcut(.escape")
        self.assertIn("if isEditing", text[i - 200:i], "Esc får inte slå PÅ redigeringsläget")


    def test_a_paragraph_is_edited_in_one_field(self):
        # Ett fält per segment bröt styckets löpande text i flera rader (0.7.8 hoppade).
        para = (self.DETAIL / "ParagraphRow.swift").read_text(encoding="utf-8")
        editing = para[para.index("if isEditing"):para.index("} else {", para.index("if isEditing"))]
        self.assertIn("ParagraphEditor(rows: rows", editing)
        self.assertNotIn("SegmentEditor", editing)
        self.assertNotIn("ForEach", editing)
        row = (self.DETAIL / "SegmentRow.swift").read_text(encoding="utf-8")
        self.assertIn("ParagraphEditing.split", row, "Ändringen förs tillbaka till segmenten med den testade funktionen")
        # SwiftUI:s TextField ignorerar .lineSpacing: fältet blev lägre än visningen (mätt i CI).
        field = row[row.index("struct EditableText"):row.index("struct EditSurface")]
        self.assertNotIn("TextField(", field)
        self.assertIn("ReadingTextView(", field)
        self.assertIn("style.lineSpacing = lineSpacing", field)

    def test_the_paragraph_you_read_stays_put_when_the_mode_changes(self):
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        i = text.index(".onChange(of: isEditing)")
        self.assertIn("scrollAnchor.restore", text[i:i + 250])
        self.assertIn("anchor: scrollAnchor", text)
        self.assertGreaterEqual(text.count("RowFrameReporter("), 2, "Både stycken och rader rapporterar sin position")

    def test_heights_are_measured_in_ci(self):
        workflow = (ROOT / ".github/workflows/build.yml").read_text(encoding="utf-8")
        self.assertIn("./scripts/test-app.sh", workflow)
        tests = (ROOT / "TranskriberaAppTests/EditModeHeightTests.swift").read_text(encoding="utf-8")
        self.assertIn("ParagraphRow(", tests)
        self.assertIn("SegmentRow(", tests)
        self.assertIn("ReadingTextSize.steps", tests)


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
