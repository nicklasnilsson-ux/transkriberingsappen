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
        rows = sidebar[sidebar.index("private var list: some View"):]
        order = [rows.index(x) for x in ("topCards", "listHeader", "ForEach(groups)")]
        self.assertEqual(order, sorted(order))

    def test_settings_and_dropzone_are_grouped(self):
        # 0.9.11 (Nicklas skiss 2026-11-05): inställningskortet ligger ovanför rutan, i samma listrad.
        top = sidebar[sidebar.index("private var topCards"):sidebar.index("private var newTranscriptionGroup")]
        self.assertLess(top.index("settingsCard"), top.index("newTranscriptionGroup"))
        group = sidebar[sidebar.index("private var newTranscriptionGroup"):sidebar.index("private var modeSwitcher")]
        self.assertLess(group.index("modeSwitcher"), group.index("dropArea"))
        self.assertIn(".sidebarCard()", group)

    def test_dropzone_has_choose_files_and_highlight(self):
        self.assertIn('Button("Välj filer…")', sidebar)
        self.assertIn("isDropTargeted", sidebar)

    def test_title_search_still_filters_the_list(self):
        # PR #72 tog av misstag bort sökfiltret när kod raderades i ett svep (bygget föll).
        self.assertIn("private var filtered: [Transcript]", sidebar)
        self.assertIn("TextSearch.matches($0.title, query: filter)", sidebar)
        self.assertIn("filtered.filter", sidebar)

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

    def test_rerun_popover_starts_from_the_file_not_from_the_defaults(self):
        popover = (V / "Views/Detail/RerunSettingsPopover.swift").read_text(encoding="utf-8")
        # Popovern får inte läsa standardinställningarna; den visar det filen har.
        self.assertNotIn("@AppStorage", popover)
        self.assertIn("file.modelRaw", popover)
        self.assertIn("file: fileBaseline", detail)

    def test_model_chip_hides_experiment_labels(self):
        # "(Nemotron 3)", "(jämnad volym)" osv. hör till jämförelsen, inte till modellvalet.
        self.assertIn("RerunChange.baseModelName(transcript.modelName)", detail)

    def test_rerun_does_what_the_chips_show(self):
        # Ändrar man inget ska omtagningen ändå göras med filens modell, språk och talarval.
        self.assertIn("overrides.filled(with: fileBaseline)", detail)


class EmptyViewTests(unittest.TestCase):
    def test_empty_view_is_only_the_empty_state(self):
        # 0.9.11: raden med inställningar är borta ur huvudytan (de finns i sidopanelens kort).
        empty = (V / "Views/Home/FileModeEmptyView.swift").read_text(encoding="utf-8")
        view = empty[empty.index("struct FileModeEmptyView"):empty.index("struct NextTranscriptionSettingsForm")]
        self.assertIn("ContentUnavailableView", view)
        self.assertIn('.navigationTitle("Ny transkribering")', view)


class CollapseAndPlayerTests(unittest.TestCase):
    def test_scroll_is_read_from_the_real_scroll_view(self):
        # GeometryReader ensam rapporterade inte under skrollning (0.7.1 fällde inte ihop).
        self.assertRegex(detail, r"ScrollOffsetObserver[ (]")
        probe = (V / "Views/Detail/ScrollOffsetObserver.swift").read_text(encoding="utf-8")
        self.assertIn("boundsDidChangeNotification", probe)
        self.assertIn("postsBoundsChangedNotifications = true", probe)

    def test_mini_player_in_the_fixed_player_bar_with_three_sizes(self):
        bar = detail[detail.index("private var playerBar"):detail.index("private var showsRolesBanner")]
        self.assertIn("PlayerBar(", bar)
        player_bar = (V / "Views/Player/PlayerBar.swift").read_text(encoding="utf-8")
        self.assertIn("if isVideo { videoWithControls }", player_bar)
        self.assertIn("MiniPlayerSize.allCases", player_bar)


class RerunButtonTests(unittest.TestCase):
    def test_button_is_emphasized_only_when_settings_changed(self):
        self.assertIn("isChanged: rerunSettingsChanged", detail)
        popover = (V / "Views/Detail/RerunSettingsPopover.swift").read_text(encoding="utf-8")
        self.assertIn("RerunButtonStyle(isEmphasized: isChanged)", popover)
        self.assertIn("Transkribera igen", popover, "Transkribera igen ligger inne i inställningsrutan (Pianissimo)")
        self.assertIn("RerunChange.isChanged(", detail)


class MultiSelectTests(unittest.TestCase):
    def test_list_supports_multiple_selection_with_macos_standard_deselect(self):
        self.assertIn("List(selection: listSelection)", sidebar)
        # macOS-standard (Nicklas 2026-11-01): ⌘-klick och Esc avmarkerar, inte ett vanligt klick.
        content = (V / "Views/ContentView.swift").read_text(encoding="utf-8")
        self.assertIn(".onExitCommand { appState.clearSelection() }", content)
        for banned in ("addLocalMonitorForEvents", "pendingDeselectRow", "leftMouseUp"):
            self.assertNotIn(banned, sidebar)

    def test_rows_have_no_own_click_handler(self):
        # 0.7.3: en egen klickhanterare på raderna slogs med listans val (segt, bara texten svarade).
        list_code = sidebar[sidebar.index("private var list: some View"):]
        list_code = list_code[:list_code.index("private func menu(")]
        for banned in ("TapGesture", "onTapGesture", "simultaneousGesture", "highPriorityGesture"):
            self.assertNotIn(banned, list_code)

    def test_detail_shows_multi_selection_view(self):
        content = (V / "Views/ContentView.swift").read_text(encoding="utf-8")
        self.assertIn("MultiSelectionView(", content)

    def test_bulk_actions_ask_first_and_say_how_many(self):
        view = (V / "Views/Home/MultiSelectionView.swift").read_text(encoding="utf-8")
        self.assertIn("RetranscribeConfirmation(replacingText", view)
        self.assertIn("DeleteConfirmation(count:", view)
        self.assertIn("BulkRetranscribe.message(count: count,", view)
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


class WordingTests(unittest.TestCase):
    def test_new_transcription_is_never_called_next_transcription(self):
        # Samma begrepp på alla ställen: "Ny transkribering", aldrig "Nästa transkribering".
        for path in V.rglob("*.swift"):
            for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if line.lstrip().startswith("//"):
                    continue
                self.assertNotRegex(line, r"(?i)nästa transkribering", f"{path.name}:{n}: {line.strip()}")


if __name__ == "__main__":
    unittest.main()
