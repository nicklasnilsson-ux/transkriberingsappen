"""Modelltexterna får inte lova mer än mätningarna visar, och måste vara lika överallt.

Bakgrund (Nicklas 2026-11-09): kortet för KB Large ordagrann sa "när varje ord måste stämma"
och "Bäst för svenska", fast ordfelen på ren svenska är nästan lika (82,0 mot 82,4 % ord rätt,
5 mot 7 fel på 100 ord) och Pianissimo är förvald. Det KB Large faktiskt har är bättre resultat
på svagt ljud, och priset är tid och minne. Kontrollen stoppar:
- de gamla, motsägda formuleringarna i appen, på landningssidan och i README,
- påståendet "tränad på svenska dialekter" (modellkorten säger det inte: KB-Whisper nämner
  inga dialekter, Pianissimo har dialekter bara som testmängd),
- att meningen om när man väljer KB Large saknas på något av ställena, eller att märkena ändras
  utan att den här kontrollen och källkommentaren i ModelCatalog.swift uppdateras.

Kör: python3 -m unittest discover -s scripts"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = (ROOT / "Transkribera/Models/ModelCatalog.swift").read_text(encoding="utf-8")
PICKER = (ROOT / "Transkribera/Views/Settings/ModelPicker.swift").read_text(encoding="utf-8")
SITE = (ROOT / "site/index.html").read_text(encoding="utf-8")
README = (ROOT / "README.md").read_text(encoding="utf-8")

KB_SENTENCE = "Välj den när ljudet är dåligt eller du vill ha några färre ordfel."
KB_ADVICE = "när ljudet är dåligt eller du vill ha några färre ordfel"
FORBIDDEN = [
    (re.compile(r"varje ord måste stämma", re.I), "lovar mer än siffrorna (ord rätt 82,0 mot 82,4 %)"),
    (re.compile(r"Bäst för svenska"), "Pianissimo är förvald och lika bra på ord; märket ska vara mätbart"),
    (re.compile(r"tränad\w*\s+på\s+svenska\s+dialekter", re.I), "ej belagt i modellkorten"),
    (re.compile(r"citat,\s*namn\s+och\s+facktermer", re.I), "samma motsagda löfte i andra ord"),
]


class ModelTextTests(unittest.TestCase):
    def test_no_contradicted_claims(self):
        for name, text in {"ModelCatalog.swift": CATALOG, "ModelPicker.swift": PICKER,
                           "site/index.html": SITE, "README.md": README}.items():
            for pattern, why in FORBIDDEN:
                self.assertIsNone(pattern.search(text), f"{name}: '{pattern.pattern}' är förbjudet ({why})")

    def test_kb_large_text_same_everywhere(self):
        self.assertIn(KB_SENTENCE, CATALOG, "kortets text (characteristic) för KB Large ordagrann")
        self.assertIn(KB_ADVICE, PICKER, "rådet överst i väljaren och i guiden")
        self.assertGreaterEqual(PICKER.count(KB_ADVICE), 2, "både rådsrutan och guiden")
        self.assertIn(KB_SENTENCE, SITE, "landningssidan")
        self.assertIn(KB_ADVICE, README, "README")

    def test_badges(self):
        self.assertIn('case .kbLargeStrict, .kbLarge: return "Bäst på svagt ljud"', CATALOG)
        self.assertIn('case .pianissimo: return "Snabbast"', CATALOG)


if __name__ == "__main__":
    unittest.main()
