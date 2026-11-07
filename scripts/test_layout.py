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
        self.assertNotIn("Skilj på vem som pratar", controls, "talarvalet ligger i inställningskortet")
        self.assertIn(".disabled(recorder.isBusy)", controls)
        self.assertIn("NeutralProminentButtonStyle()", controls, "Stoppa är en neutral svart knapp")
        self.assertIn(".tint(Color.accentColor)", controls, "Starta är appens uppmaning (accent)")
        self.assertNotIn(".inspector(", (VIEWS / "Home" / "MeetingModeView.swift").read_text(encoding="utf-8"))
        self.assertFalse((VIEWS / "Home" / "MeetingInspector.swift").exists())


class NextTranscriptionSettingsInOnePlaceTests(unittest.TestCase):
    """Nicklas 2026-11-05: inställningarna för ny transkribering (fil och möte) finns på ett ställe,
    kortet överst i sidopanelen. Raden med väljare i huvudytan trycktes ihop och bröts mitt i orden."""

    def test_settings_for_the_next_transcription_are_only_changed_in_the_card(self):
        # Vyer som skriver till inställningarna för nästa transkribering. Appens Inställningar… (⌘,) räknas inte.
        allowed = {"Home/FileModeEmptyView.swift", "Settings/SettingsView.swift"}
        keys = ["SettingsKey.model)", "SettingsKey.language)", "SettingsKey.identifySpeakers)",
                "SettingsKey.speakers)", "SettingsKey.vocabulary)"]
        hits = []
        for path in VIEWS.rglob("*.swift"):
            rel = path.relative_to(VIEWS).as_posix()
            text = path.read_text(encoding="utf-8")
            for key in keys:
                for line in text.splitlines():
                    if "@AppStorage(" + key in line and rel not in allowed and rel != "Sidebar/SidebarView.swift":
                        hits.append(f"{rel}: {line.strip()}")
        self.assertEqual(hits, [], "inställningar för ny transkribering utanför kortet")
        # Sidopanelen läser dem bara för sammanfattningen; själva valen finns i formuläret.
        sidebar = (VIEWS / "Sidebar" / "SidebarView.swift").read_text(encoding="utf-8")
        for control in ("ModelPicker(", "Toggle(", "SwitchRow(", "SpeakerCountPicker(", "TextField(\"Ordlista"):
            self.assertNotIn(control, sidebar, control)
        form = (VIEWS / "Home" / "FileModeEmptyView.swift").read_text(encoding="utf-8")
        form = form[form.index("struct NextTranscriptionSettingsForm"):]
        for control in ("ModelPicker(", "Picker(\"Språk\"", "Skilj på vem som pratar", "SpeakerCountPicker(", "Ordlista"):
            self.assertIn(control, form, control)

    def test_no_row_of_pickers_in_the_main_area(self):
        empty = (VIEWS / "Home" / "FileModeEmptyView.swift").read_text(encoding="utf-8")
        view = empty[empty.index("struct FileModeEmptyView"):empty.index("struct NextTranscriptionSettingsForm")]
        for banned in ("NextTranscriptionChips", "ChipButton", "HStack", "Picker"):
            self.assertNotIn(banned, view, banned)
        for path in VIEWS.rglob("*.swift"):
            self.assertNotIn("NextTranscriptionChips", path.read_text(encoding="utf-8"), path.name)

    def test_card_sits_above_the_new_transcription_box_and_locks_while_recording(self):
        sidebar = (VIEWS / "Sidebar" / "SidebarView.swift").read_text(encoding="utf-8")
        top = sidebar[sidebar.index("private var topCards"):sidebar.index("private var newTranscriptionGroup")]
        self.assertLess(top.index("settingsCard"), top.index("newTranscriptionGroup"))
        card = sidebar[sidebar.index("private var settingsCard"):sidebar.index("private var dropArea")]
        self.assertIn(".disabled(recorder.isBusy)", card)
        self.assertIn("NextTranscriptionSettingsForm()", card)
        self.assertIn("NextTranscriptionSummary(", card)
        label = sidebar[sidebar.index("struct SettingsCardLabel"):]
        label = label[:label.index("\n}\n")]
        self.assertEqual(label.count("Text("), label.count(".lineLimit(1)"), "varje rad i kortet ska vara en rad")


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
        block = text[start:text.index("private func requestRetranscribe", start)]
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
        self.assertIn("editingID == paragraph.first?.segment.persistentModelID", text)
        para = (self.DETAIL / "ParagraphRow.swift").read_text(encoding="utf-8")
        row = (self.DETAIL / "SegmentRow.swift").read_text(encoding="utf-8")
        # 0.9.0: ett klick på markerbar text öppnade aldrig redigering (Nicklas 2026-11-04). Nu öppnas det
        # med knappen "Redigera" som visas när musen står över stycket, så att texten går att markera.
        self.assertNotIn("onTapGesture { onBeginEdit() }", para + row, "Klick på markerbar text sväljs på macOS")
        # Knappen finns alltid med i stycket (osynlig vid rättning), annars byter stycket höjd (CI 2026-11-04: 1 pt).
        self.assertIn("RowEditActions(", para)
        self.assertIn("RowEditActions(", row)
        self.assertNotIn("if !isEditing { EditHoverButton", para)
        actions = row[row.index("struct RowEditActions"):row.index("struct EditHoverButton")]
        self.assertIn('Button("Avbryt"', actions, "Avbryt och Spara ersätter Redigera vid stycket (Nicklas 2026-11-04)")
        self.assertIn('Button("Spara"', actions)
        self.assertIn("EditHoverButton(visible: hovering && !isEditing", actions)
        self.assertIn(".frame(minHeight: 22)", para, "Raden har fast höjd, så att Spara/Avbryt inte ändrar styckets höjd")
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
        bar_src = (VIEWS / "Player/PlayerBar.swift").read_text(encoding="utf-8")
        button = (VIEWS / "Player/PlayPauseButton.swift").read_text(encoding="utf-8")
        # Rund platta i accentfärgen, med fast storlek: dubbelt så stor som i 0.9.2–0.9.14 (Nicklas 2026-11-06).
        # Själva storleken mäts i TranskriberaAppTests/PlayButtonSizeTests.swift.
        self.assertIn("Circle().fill(Color.accentColor)", button, "Play/Pause ligger på en rund platta i accentfärgen")
        self.assertIn("static let diameter: CGFloat = 56", button)
        self.assertIn("PlayPauseButton(isPlaying: player.isPlaying)", bar_src)
        self.assertNotIn("Button { player.togglePlayPause() }", text, "Spela/Pausa finns bara i PlayerBar")
        bar = text[text.index("private var playerBar"):text.index("private var showsRolesBanner")]
        self.assertIn("PlayerBar(", bar)
        row = bar_src[bar_src.index("private func row(followTitle"):][:600]
        self.assertIn("videoWithControls", row)
        self.assertNotIn("sizeMenu", row, "Bildstorlek ligger närmast videon, inte längst till höger")
        # Reglaget är det enda som växer och krymper; det får en minsta bredd.
        self.assertIn("minWidth: Self.sliderMinWidth, idealWidth: Self.sliderMinWidth, maxWidth: .infinity", bar_src)
        video = bar_src[bar_src.index("private var videoWithControls"):][:400]
        self.assertLess(video.index("miniPlayer"), video.index("sizeMenu"))
        # Eget fönster ligger i samma lilla meny som bildstorlekarna och ersätter Helskärm (Nicklas 2026-11-07).
        menu = bar_src[bar_src.index("private var sizeMenu"):][:1100]
        self.assertIn("Picker(\"Bildstorlek\"", menu)
        self.assertIn("Visa i eget fönster", menu)
        self.assertIn("videoWindow.open(player: player.player", menu)
        self.assertIn("Tillbaka till spelarraden", menu, "Menyn lägger tillbaka videon när den visas i eget fönster")
        self.assertNotIn("Helskärm", menu, "Helskärm är ersatt av eget fönster")
        self.assertFalse((VIEWS / "Player/VideoFullscreen.swift").exists())
        # Videon spelas aldrig på två ställen: i eget fönster står en platshållare i spelarraden.
        mini = bar_src[bar_src.index("private var miniPlayer"):][:700]
        self.assertIn("if inOwnWindow", mini)
        self.assertLess(mini.index("backHerePlaceholder"), mini.index("PlayerView("),
                        "PlayerView visas bara när videon inte är i eget fönster")
        holder = bar_src[bar_src.index("private var backHerePlaceholder"):][:500]
        self.assertIn("videoWindow.close()", holder)
        self.assertIn("Tillbaka hit", holder)
        win = (VIEWS / "Player/VideoWindow.swift").read_text(encoding="utf-8")
        self.assertIn(".resizable", win, "Fönstret går att dra i hörnet")
        self.assertIn("setFrameAutosaveName", win, "Storlek och plats sparas")
        self.assertIn("willCloseNotification", win, "Stängt fönster lägger tillbaka videon")
        self.assertNotIn("toggleFullScreen", win, "Fönstret öppnas som vanligt fönster, inte i helskärm")
        # Fönstret lade sig bakom huvudfönstret vid klick där (Nicklas 2026-11-07): flytande medan appen är aktiv,
        # vanligt när en annan app är aktiv eller i helskärm. Nivån sätts när fönstret öppnas och när appen byter läge.
        self.assertIn("appIsActive ? .floating : .normal", win)
        self.assertIn("didBecomeActiveNotification", win)
        self.assertIn("didResignActiveNotification", win)
        self.assertIn("willEnterFullScreenNotification", win)
        opened = win[win.index("func open("):win.index("func close()")]
        self.assertIn("updateLevel()", opened, "Nivån sätts direkt när fönstret öppnas")
        # Fönstret hör till filen: det stängs när filen byts eller vyn försvinner.
        detail = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        gone = detail[detail.index(".onDisappear {", detail.index("private struct DetailLifecycle")):][:300]
        self.assertIn("VideoWindow.shared.closeIfShowing(player.player)", gone)

    def test_edit_all_and_edit_one_both_work(self):
        # Nicklas 2026-11-04: Redigera i titelbaren öppnar alla stycken, knappen vid ett stycke öppnar bara det.
        text = (self.DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        self.assertIn("@State private var editsAll", text)
        self.assertIn("private var isEditing: Bool { editsAll || editingID != nil }", text)
        toggle = text[text.index("private var editToggle"):][:1200]
        self.assertIn("beginEditingAll()", toggle)
        self.assertIn("isEditing: editsAll || editingID ==", text)
        self.assertIn("editsAll: editsAll", text)
        row = (self.DETAIL / "SegmentRow.swift").read_text(encoding="utf-8")
        self.assertIn("func saveAll()", row)
        self.assertIn("func discardAll()", row)
        self.assertIn("autofocus", row)
        self.assertIn("editSession.autofocus = false", text, "Alla fält får inte ta fokus på en gång")

    def test_sidebar_is_one_scroll_view_from_the_top(self):
        # Nicklas 2026-11-04 (fyra gånger): panelen centrerades, hoppade och tryckte sig ut ovanför fönstret.
        # Allt ligger nu som rader i en enda lista: ingen mätning, ingen centrering, ingen egen höjd.
        side = (VIEWS / "Sidebar/SidebarView.swift").read_text(encoding="utf-8")
        body = side[side.index("var body: some View"):side.index(".navigationSplitViewColumnWidth")]
        for forbidden in ("ViewThatFits", "GeometryReader", "ScrollView", "VStack", "fixedSize", ".frame("):
            self.assertNotIn(forbidden, body, f"{forbidden} i panelens body kan flytta innehållet")
        lst = side[side.index("private var list: some View"):side.index("/// Frågar först")]
        self.assertIn("topCards.sidebarPlainRow()", lst, "Inställningskortet och rutan är första raden i samma lista")
        self.assertIn("listHeader.sidebarPlainRow()", lst, "Rubrik och sökfält scrollar med")
        self.assertLess(lst.index("topCards"), lst.index("listHeader"))
        self.assertLess(lst.index("listHeader"), lst.index("ForEach(groups)"))
        helper = side[side.index("func sidebarPlainRow"):]
        self.assertIn(".selectionDisabled()", helper)
        self.assertIn(".listRowInsets(EdgeInsets(top: 0, leading: SidebarLayout.plainRowInset", helper)

    def test_meeting_controls_use_full_width_with_air_between_rows(self):
        text = (VIEWS / "Home/MeetingControls.swift").read_text(encoding="utf-8")
        self.assertIn("struct SwitchRow", text)
        self.assertIn('SwitchRow("Spela även in min mikrofon"', text)
        self.assertNotIn(".fixedSize()", text[:text.index("private struct SwitchRow")], "Talarväljaren sträcks över hela bredden")
        self.assertIn(".frame(maxWidth: .infinity)", text)
        self.assertIn("spacing: 16", text)

    def test_rows_and_paragraphs_have_the_same_text_width(self):
        # Nicklas 2026-11-04: texten var smalare i styckevisningen än i radvisningen.
        para = (self.DETAIL / "ParagraphRow.swift").read_text(encoding="utf-8")
        row = (self.DETAIL / "SegmentRow.swift").read_text(encoding="utf-8")
        self.assertIn("ReadingTextSize.columnWidth(for: readingSize)", para)
        seg = row[row.index("struct SegmentRow"):row.index("struct RowEditActions")]
        self.assertIn("ReadingTextSize.columnWidth(for: readingSize)", seg)
        self.assertEqual(seg.count("maxWidth: textWidth"), 2, "Både visning och redigering har spaltbredden")

    def test_hover_edit_button_matches_cancel_and_save(self):
        row = (self.DETAIL / "SegmentRow.swift").read_text(encoding="utf-8")
        hover = row[row.index("struct EditHoverButton"):][:900]
        self.assertIn(".buttonStyle(.bordered)", hover, "Samma stil som Avbryt")
        self.assertIn(".controlSize(.small)", hover)

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


class MeetingViewHeightTests(unittest.TestCase):
    """Felet i Mötesinspelning 0.9.0–0.9.5: en text med fixedSize(vertical: true) i detaljvyn gjorde
    splitvyn ca 1340 pt hög, så sidopanelen hamnade ovanför appens överkant. Apptestet
    WindowLayoutTests mäter det på CI; här stoppas mönstret redan i källkoden."""

    def test_sidebar_uses_one_side_margin_for_everything(self):
        """Rutan, rubriken och sökfältet hade andra sidkanter än markeringen (0.9.7). Kanterna mäts i pixlar av
        apptestet SidebarMarginTests; här kontrolleras att det finns och att panelen inte har egna sidmarginaler."""
        src = (VIEWS / "Sidebar" / "SidebarView.swift").read_text(encoding="utf-8")
        body = src[:src.index("private enum SidebarLayout")]
        self.assertNotIn(".padding(.horizontal, 12)", body)
        self.assertNotIn(".padding(.horizontal, 14)", body)
        self.assertIn("SidebarLayout.plainRowInset", src)
        test = (ROOT / "TranskriberaAppTests" / "SidebarMarginTests.swift").read_text(encoding="utf-8")
        self.assertIn("abs(box.left - selected.left)", test)
        self.assertIn("abs(search.right - selected.right)", test)

    def test_sidebar_rows_are_single_accessibility_elements(self):
        """Skärmläsare ska läsa en rad som en mening (titel, längd, datum, status), inte som lösa texter."""
        src = (VIEWS / "Sidebar" / "SidebarView.swift").read_text(encoding="utf-8")
        row = src[src.index("private struct SidebarRow"):src.index("/// Rubrik i lägesväxlaren")]
        self.assertIn(".accessibilityElement(children: .ignore)", row)
        self.assertIn(".accessibilityLabel(accessibilityText)", row)

    def test_selected_sidebar_row_flips_its_text_colours(self):
        """Appens egna textfärger vänds inte av systemet på markerade rader (mörk text på mörk
        markering, 2026-11-05). Raden måste därför själv läsa backgroundProminence."""
        src = (VIEWS / "Sidebar" / "SidebarView.swift").read_text(encoding="utf-8")
        row = src[src.index("private struct SidebarRow"):src.index("/// Rubrik i lägesväxlaren")]
        # backgroundProminence räckte inte (0.9.7: fortfarande mörk text). Raden får veta att den är vald.
        self.assertIn("let isSelected: Bool", row)
        self.assertIn("isSelected && activeState != .inactive", row)
        self.assertIn("isSelected: listSelection.wrappedValue.contains(transcript)", src)
        self.assertNotIn("Color.textSecondary", row, "använd secondaryColor, som vänder på markerad rad")
        self.assertNotIn(".tint)", row)

    def test_meeting_view_has_no_vertically_fixed_text(self):
        # Chipsraden i Fil-läget har en enradig fixedSize och mättes som oskyldig (626 pt); bara mötesvyn har löpande text.
        for name in ("Home/MeetingModeView.swift",):
            text = (VIEWS / name).read_text(encoding="utf-8")
            code = "\n".join(l for l in text.splitlines() if not l.strip().startswith("//"))
            self.assertNotIn("fixedSize(horizontal: false, vertical: true)", code, name)

    def test_window_layout_test_covers_both_modes(self):
        text = (ROOT / "TranskriberaAppTests" / "WindowLayoutTests.swift").read_text(encoding="utf-8")
        self.assertIn("mode: .meeting", text)
        self.assertIn("mode: .file", text)
        self.assertNotIn("XCTFail", text, "Diagnosen ska vara en riktig kontroll")


if __name__ == "__main__":
    unittest.main()
