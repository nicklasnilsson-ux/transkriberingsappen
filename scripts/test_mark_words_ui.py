"""Kontroll: "Markera ord att lyssna på" heter så överallt där användaren ser det, och
valen för Pianissimo i 16/32 bitar är borta ur Inställningar och Testlabbets listor.

2026-11-13: 8, 16 och 32 bitar mättes lika på fyra inspelningar, och Nicklas valde namnet
"Markera ord att lyssna på" i stället för "Korskolla". Ett sparat 16/32-bitarsval får inte
leva kvar osynligt.
Kör: python3 -m unittest discover -s scripts"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SETTINGS = (ROOT / "Transkribera/Views/Settings/SettingsView.swift").read_text(encoding="utf-8")
OPTIONS = (ROOT / "Transkribera/Models/AppSettings.swift").read_text(encoding="utf-8")
PLAN = (ROOT / "Packages/TranskriberaCore/Sources/TranskriberaCore/TestLabPlan.swift").read_text(encoding="utf-8")
LABVIEW = (ROOT / "Transkribera/Views/TestLab/TestLabView.swift").read_text(encoding="utf-8")


class MarkWordsUITests(unittest.TestCase):
    def test_name_in_settings(self):
        self.assertIn('Toggle("Markera ord att lyssna på"', SETTINGS)
        self.assertNotIn("Korskolla", SETTINGS)

    def test_precision_choices_are_gone(self):
        self.assertNotIn("PianissimoVersion", SETTINGS)
        self.assertNotIn("PianissimoVersion.current", OPTIONS, "Ett gammalt sparat val skulle annars gälla osynligt")
        self.assertIn("ForEach(TestLabPlan.Kind.offered)", LABVIEW)
        offered = PLAN[PLAN.index("static let offered"):].split("\n")[0]
        self.assertNotIn(".precision", offered)
        self.assertIn(".crossCheck", offered)

    def test_old_comparison_list_is_gone(self):
        # 13 inställningar och fyllnadsordsledtrådar provades 2026-10-31: inget hjälpte.
        self.assertNotIn("case comparison", PLAN)
        self.assertNotIn("public static let standard", PLAN)
        self.assertNotIn("Jämför inställningar", PLAN)


if __name__ == "__main__":
    unittest.main()
