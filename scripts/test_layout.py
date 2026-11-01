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
