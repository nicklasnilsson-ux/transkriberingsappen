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

    def test_mode_switcher_is_in_the_sidebar_not_the_toolbar(self):
        # Pianissimo: titelbaren är fri för det som hör till den öppnade texten.
        content = (VIEWS / "ContentView.swift").read_text(encoding="utf-8")
        self.assertNotIn("ToolbarItem", content)
        text = (VIEWS / "Sidebar" / "SidebarView.swift").read_text(encoding="utf-8")
        self.assertIn("private var modeSwitcher", text)
        self.assertIn(".pickerStyle(.segmented)", text)

    def test_sidebar_groups_come_from_the_tested_core_function(self):
        text = (VIEWS / "Sidebar" / "SidebarView.swift").read_text(encoding="utf-8")
        self.assertIn("SidebarGroup.group(", text)


class MeetingModeTests(unittest.TestCase):
    def test_no_live_text_during_recording(self):
        # Beslut: möte = inspelningsstatus, texten skapas först när inspelningen stoppas.
        for name in ("Home/MeetingModeView.swift", "Home/MeetingControls.swift", "Home/FileModeEmptyView.swift"):
            text = (VIEWS / name).read_text(encoding="utf-8")
            self.assertNotIn("liveText", text, name)

    def test_meeting_settings_replace_the_drop_area_and_lock_while_recording(self):
        # Pianissimo (Nicklas 2026-11-03): man gör en sak i taget. Inställningarna ersätter släppytan
        # i sidopanelen och är låsta under inspelning; Starta/Stoppa ligger i panelen.
        sidebar = (VIEWS / "Sidebar" / "SidebarView.swift").read_text(encoding="utf-8")
        self.assertRegex(sidebar, r"if appState\.mode == \.meeting \{\s*MeetingControls\(\)\s*\} else \{\s*dropArea")
        controls = (VIEWS / "Home" / "MeetingControls.swift").read_text(encoding="utf-8")
        self.assertIn("Spela även in min mikrofon", controls)
        self.assertIn("Skilj på vem som pratar", controls)
        self.assertIn(".disabled(recorder.isBusy)", controls)
        self.assertIn("NeutralProminentButtonStyle()", controls, "Stoppa är en neutral svart knapp")
        self.assertIn(".tint(Color.accentColor)", controls, "Starta är appens uppmaning (accent)")
        self.assertNotIn(".inspector(", (VIEWS / "Home" / "MeetingModeView.swift").read_text(encoding="utf-8"))
        self.assertFalse((VIEWS / "Home" / "MeetingInspector.swift").exists())


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
        block = text[start:text.index("private func miniPlayer", start)]
        self.assertNotIn("isEditing", block, "Kortet ovanför texten får inte bero på redigeringsläget (layouten hoppar)")
        roles = text[text.index("private var showsRolesBanner"):][:200]
        self.assertNotIn("!isEditing", roles, "Rollbannern får inte försvinna när redigeringsläget slås på (layouten hoppar)")
        header = text[text.index("private var headerRow"):text.index("private var fileBaseline") if text.index("private var fileBaseline") > text.index("private var headerRow") else None]
        self.assertNotIn("isEditing", header, "Raden överst ändras inte av redigeringsläget (layouten hoppar)")

    def test_titlebar_has_search_edit_and_more_in_that_order(self):
        # Pianissimo (Nicklas 2026-11-03): Sök, Redigera och ⋯ ligger alltid i titelbaren. Texten om
        # redigeringen står före knappen, så att ingenting annat flyttar sig när den visas.
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        bar = text[text.index("private var detailToolbar"):text.index("private var moreMenu")]
        order = ["olderVersionBadge", "toolbarSearch", "editStateLabel", "editToggle", "moreMenu"]
        positions = [bar.index(t) for t in order]
        self.assertEqual(positions, sorted(positions))
        self.assertIn(".toolbar { detailToolbar }", text)
        self.assertIn('"Redigerar anonymiserad text"', text)
        self.assertNotIn('"Rättar anonymiserad text"', text)

    def test_header_and_tools_follow_the_handoff(self):
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        tools = text[text.index("private var toolsRow"):text.index("private var fileBaseline")] if text.index("private var toolsRow") < text.index("private var fileBaseline") else text[text.index("private var toolsRow"):][:500]
        order = ["layoutPicker", "speakersMenu", "anonymizeToggle", "copyButton", "exportMenu()"]
        positions = [tools.index(t) for t in order]
        self.assertEqual(positions, sorted(positions), "Verktygsraden: Stycken/Rader, Talare, Anonymisera, Kopiera, Exportera")
        scroll = text[text.index("private func mainScroll"):text.index(".frame(maxWidth: 820)")]
        order = ["headerRow", "olderVersionStrip", "toolsRow", "noticeCard", "textArea("]
        positions = [scroll.index(t) for t in order]
        self.assertEqual(positions, sorted(positions))
        header = text[text.index("private var headerRow"):text.index("private var toolsRow")]
        order = ["versionPicker", "settingsPill"]
        positions = [header.index(t) for t in order]
        self.assertEqual(positions, sorted(positions))
        self.assertNotIn("interviewerPill", text, "Intervjuaren väljs under Talare, inget märke efter titeln")

    def test_the_tools_are_also_in_the_more_menu(self):
        # Nicklas 2026-11-03: verktygen finns både i raden och i ⋯-menyn, så att de nås när raden skrollat bort.
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        menu = text[text.index("private var moreMenu"):text.index("/// Alla träffar i den text som visas")]
        for item in ("$layout", "$anonymize", "speakersMenuContent", "copyText()", "exportMenuContent", "requestRetranscribe()"):
            self.assertIn(item, menu, f"{item} saknas i ⋯-menyn")

    def test_on_states_are_filled_and_keep_their_size(self):
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        self.assertIn(".modifier(OnStateButtonStyle(isOn: anonymize))", text)
        export = text[text.index("private func exportMenu"):text.index("private var exportMenuContent")]
        self.assertNotIn("borderedProminent", export, "Fylld betyder att ett läge är på; Exportera är ingen växel")
        self.assertIn("Color.neutralButton", export, "Exportera är en neutral svart primärknapp")

    def test_escape_shortcut_only_exists_while_editing(self):
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        i = text.index(".keyboardShortcut(.escape")
        self.assertIn("if isEditing", text[i - 200:i], "Esc får inte slå PÅ redigeringsläget")


    def test_one_paragraph_is_edited_at_a_time(self):
        # Nicklas 2026-11-03: klick i texten öppnar ETT stycke. Inget globalt redigeringsläge längre.
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        self.assertIn("@State private var editingID: PersistentIdentifier?", text)
        self.assertNotIn("@State private var isEditing", text)
        self.assertIn("private var isEditing: Bool { editingID != nil }", text)
        self.assertIn("editingID == paragraph.first?.segment.persistentModelID", text)
        para = (self.DETAIL / "ParagraphRow.swift").read_text(encoding="utf-8")
        row = (self.DETAIL / "SegmentRow.swift").read_text(encoding="utf-8")
        # 0.9.0: ett klick på markerbar text öppnade aldrig redigering (Nicklas 2026-11-04). Nu öppnas det
        # med knappen "Redigera" som visas när musen står över stycket, så att texten går att markera.
        self.assertNotIn("onTapGesture { onBeginEdit() }", para + row, "Klick på markerbar text sväljs på macOS")
        self.assertIn("EditHoverButton(visible: hovering, action: onBeginEdit)", para)
        self.assertIn("EditHoverButton(visible: hovering, action: onBeginEdit)", row)
        self.assertIn(".textSelection(.enabled)", para, "Texten ska gå att markera och kopiera")

    def test_escape_discards_and_retur_or_click_outside_saves(self):
        row = (self.DETAIL / "SegmentRow.swift").read_text(encoding="utf-8")
        coordinator = row[row.index("func textView(_ view: NSTextView, doCommandBy"):row.index("struct EditSurface")]
        esc = coordinator[coordinator.index("cancelOperation"):coordinator.index("default:")]
        self.assertIn("parent.cancel()", esc)
        self.assertNotIn("commit()", esc, "Esc får inte spara")
        self.assertNotIn("makeFirstResponder", esc, "Att lämna fältet sparar; Esc ska förkasta")
        for editor in ("struct SegmentEditor", "struct ParagraphEditor"):
            body = row[row.index(editor):]
            body = body[:body.index("\n}\n")]
            self.assertIn("guard isEditable, !discarded", body, "Ett förkastat stycke får inte sparas när fältet försvinner")
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        self.assertIn("if isEditing { saveEditing() }", text, "Klick utanför sparar")

    def test_unsaved_paragraph_is_saved_before_version_export_copy_and_rerun(self):
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        for fn in ("private func switchVersion", "private func copyText", "private func requestRetranscribe", "private func export(as"):
            start = text.index(fn)
            self.assertIn("saveEditing()", text[start:start + 400], f"{fn} måste spara det öppna stycket först")

    def test_undo_restores_word_timings_and_is_cleared_by_a_new_paragraph(self):
        row = (self.DETAIL / "SegmentRow.swift").read_text(encoding="utf-8")
        self.assertIn("wordsData: $0.segment.wordsData", row)
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        begin = text[text.index("private func beginEditing"):][:300]
        self.assertIn("lastEdit = nil", begin)
        undo = text[text.index("private func undoLastEdit"):][:500]
        self.assertIn("segment.wordsData = entry.wordsData", undo)

    def test_titlebar_buttons_have_text(self):
        # Nicklas 2026-11-04: text på alla knappar i titelbaren utom Sök och ⋯. macOS visar bara ikonen
        # för en Label om inte labelStyle(.titleAndIcon) sätts.
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        for anchor in ('Label("Redigera", icon: .edit)', 'Label("Sparat", icon: .check)', "Label(label, icon: .clock)"):
            i = text.index(anchor)
            self.assertIn(".labelStyle(.titleAndIcon)", text[i:i + 120], f"{anchor} måste visa text")
        for anchor in ('Button("Spara")', 'Button("Avbryt")', 'Button("Ångra")'):
            self.assertIn(anchor, text)

    def test_player_controls(self):
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        play = text[text.index("private func playPauseAndTime"):][:900]
        self.assertIn("size: 28", play, "Play/Pause är dubbelt så stor som förut (14 -> 28)")
        bar = text[text.index("private var playerBar"):text.index("private var showsRolesBanner")]
        self.assertIn("videoWithControls(player)", bar)
        self.assertNotIn("sizeMenu", bar, "Bildstorlek ligger närmast videon, inte längst till höger")
        video = text[text.index("private func videoWithControls"):][:700]
        self.assertLess(video.index("miniPlayer(player)"), video.index("sizeMenu"))
        self.assertIn("VideoFullscreen.present(player: player.player)", video)
        full = (VIEWS / "Player/VideoFullscreen.swift").read_text(encoding="utf-8")
        self.assertIn("toggleFullScreen", full)
        self.assertIn("didExitFullScreenNotification", full, "Esc lämnar helskärmen och stänger fönstret")

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


class SearchTests(unittest.TestCase):
    """Sökningen fungerar som ⌘F (0.7.13). Förut filtrerades texten, så att den krympte, raden
    fälldes ut och sökfältet tappade fokus efter två bokstäver."""
    DETAIL = VIEWS / "Detail"

    def setUp(self):
        self.text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")

    def test_whole_text_stays_visible(self):
        self.assertNotIn("showOnlyMatches", self.text)
        self.assertNotIn(".filter { TextSearch.matches", self.text)
        self.assertNotIn("filter { paragraph in paragraph.contains { TextSearch", self.text)

    def test_hits_can_be_stepped_through(self):
        self.assertIn("TextSearch.positionLabel(", self.text)
        self.assertIn('.onSubmit { stepHit(forward: true) }', self.text)
        self.assertIn('.keyboardShortcut("g", modifiers: .command)', self.text)
        self.assertIn('.keyboardShortcut("g", modifiers: [.command, .shift])', self.text)
        self.assertIn("proxy.scrollTo(hit.id, anchor: .center)", self.text)
        self.assertIn("currentOccurrence", (self.DETAIL / "SegmentText.swift").read_text(encoding="utf-8"))

    def test_search_field_is_always_in_the_titlebar_and_shrinks(self):
        self.assertIn("private var toolbarSearch", self.text)
        self.assertIn("minWidth: 140", self.text, "Sökfältet krymper när fönstret är smalt")
        self.assertIn('.keyboardShortcut("f")', self.text)
        self.assertIn("searchFocused = true", self.text, "⌘F flyttar markören till sökfältet")

    def test_player_is_fixed_under_the_titlebar_and_nothing_collapses(self):
        body = self.text[self.text.index("var body: some View"):self.text.index("private func mainScroll")]
        self.assertLess(body.index("playerBar"), body.index("ScrollViewReader"), "Spelaren ligger utanför skrollytan")
        for gone in ("isCollapsed", "collapsedBar", "TitleCardCollapse", "updateCollapse"):
            self.assertNotIn(gone, self.text, f"{gone}: titelkortet fälls inte längre ihop")


class RolePromptTests(unittest.TestCase):
    """Pianissimo: valet av intervjuare får en Klar-rad med Ångra, och spela-knappen vid varje talare finns kvar."""

    def test_role_choice_can_be_undone_and_play_button_stays(self):
        text = (VIEWS / "Detail" / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        self.assertIn("chooseInterviewer(speaker)", text)
        self.assertIn("transcript.restoreSpeakers(choice.before)", text)
        self.assertIn('Button("Ångra")', text)
        self.assertIn('.help("Lyssna på \\(speaker)")', text)
        tests = (ROOT / "TranskriberaAppTests" / "RoleChoiceTests.swift").read_text(encoding="utf-8")
        self.assertIn("restoreSpeakers", tests)


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
            self.assertIn("RetranscribeSheet(", text, name)

if __name__ == "__main__":
    unittest.main()


class DropDuringRecordingTests(unittest.TestCase):
    """Filer som släpps under en mötesinspelning ska vänta i kön och inte byta vy
    (annars försvinner Stoppa-knappen). Logiken testas i Core (QueueHoldsTests);
    här kontrolleras att den är inkopplad."""

    def test_content_view_asks_the_tested_rule_before_navigating(self):
        text = (VIEWS / "ContentView.swift").read_text(encoding="utf-8")
        self.assertIn("ImportNavigation.shouldNavigate(recordingBusy: recorder.isBusy)", text)
        self.assertEqual(text.count("queue.importFiles("), 1, "Släpp och Öppna filer ska dela importvägen")

    def test_recorder_busy_state_reaches_the_queue(self):
        app = (ROOT / "Transkribera" / "App" / "TranskriberaApp.swift").read_text(encoding="utf-8")
        self.assertIn("setRecordingBusy(", app)
        recorder = (ROOT / "Transkribera" / "Services" / "MeetingRecorder.swift").read_text(encoding="utf-8")
        self.assertNotIn("        state = .", recorder, "Tillståndet ska bytas via setState så att kön får veta")
        queue = (ROOT / "Transkribera" / "Services" / "TranscriptionQueue.swift").read_text(encoding="utf-8")
        self.assertIn("!self.isHeld", queue, "Arbetstråden ska stanna när kön hålls")
