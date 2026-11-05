"""Kontroll: Testlabbet är ett utvecklingsverktyg och ska inte synas för vanliga användare.
Det får inte finnas som menyval eller synlig knapp, bara via den dolda genvägen.
Kör: python3 -m unittest discover -s scripts"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = (ROOT / "Transkribera" / "App" / "TranskriberaApp.swift").read_text(encoding="utf-8")


class TestLabHiddenTests(unittest.TestCase):
    def test_no_menu_entry_or_visible_label(self):
        self.assertNotIn('Button("Testlabb', APP)
        commands = APP[APP.index(".commands {"):APP.index("Settings {")]
        self.assertNotIn("TestLab", commands, "Testlabbet får inte ligga i en meny")

    def test_not_a_window_scene_because_those_are_listed_in_the_window_menu(self):
        # En Window-scen listas alltid i Fönster-menyn (Nicklas 2026-11-04). Därför eget AppKit-fönster.
        self.assertNotRegex(APP, r'Window\("Testlabb')
        self.assertNotRegex(APP, r'(Window|WindowGroup)\([^)]*TestLab')
        self.assertIn("NSHostingController(rootView: root)", APP)

    def test_window_opens_only_through_hidden_shortcut(self):
        self.assertIn("struct TestLabShortcut", APP)
        self.assertRegex(APP, r'\.keyboardShortcut\("t", modifiers: \[\.command, \.option, \.shift\]\)')
        self.assertIn(".opacity(0)", APP)
        self.assertIn(".accessibilityHidden(true)", APP)
        self.assertEqual(len(re.findall(r"TestLabWindow\.show\(", APP)), 1)


class MainWindowTests(unittest.TestCase):
    """Stänger man huvudfönstret ska det gå att öppna igen (Nicklas 2026-11-04)."""

    def test_single_window_scene_so_it_is_listed_and_reopenable(self):
        self.assertRegex(APP, r'Window\("Transkribera", id: MainWindow\.id\)')
        self.assertNotIn("WindowGroup", APP)

    def test_file_menu_can_reopen_the_window(self):
        # CommandGroup(replacing: .newItem) tar bort "Nytt fönster", så vi lägger tillbaka ett sätt.
        self.assertIn("ShowMainWindowButton()", APP[APP.index("replacing: .newItem"):])
        self.assertIn("openWindow(id: MainWindow.id)", APP)

    def test_dock_click_reopens_the_window(self):
        self.assertIn("applicationShouldHandleReopen", APP)
        self.assertIn("@NSApplicationDelegateAdaptor(AppDelegate.self)", APP)


if __name__ == "__main__":
    unittest.main()
