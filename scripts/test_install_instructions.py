"""Kontroll: instruktionerna för att öppna appen första gången och slå på mötesinspelning
(Nicklas 2026-11-10: ska vara väldigt lätta att förstå och följa). Landningssidan, README och
felmeddelandet i appen ska använda samma exakta menynamn som macOS, ha numrerade steg och säga
vad man ser när det lyckats. Menynamnen får inte glida isär mellan ställena.
Kör: python3 -m unittest discover -s scripts"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = (ROOT / "site" / "index.html").read_text(encoding="utf-8")
README = (ROOT / "README.md").read_text(encoding="utf-8")
RECORDER = (ROOT / "Transkribera" / "Services" / "MeetingRecorder.swift").read_text(encoding="utf-8")

# Namn som användaren ska se i macOS. Stavningen är macOS egen.
GATEKEEPER = ["Systeminställningar › Integritet och säkerhet", "Öppna ändå", "Klar", "OK"]
PERMISSION = ["Systeminställningar › Integritet och säkerhet", "Skärm- och systemljudsinspelning", "Skärminspelning"]
RESET = ["−", "+"]


def plain(text: str) -> str:
    return " ".join(re.sub(r"<[^>]+>", "", text).replace("*", "").split())


class InstallInstructionTests(unittest.TestCase):
    def test_gatekeeper_steps_use_the_same_names_everywhere(self):
        for name, text in (("site", plain(SITE)), ("README", plain(README))):
            for term in GATEKEEPER:
                self.assertIn(term, text, f"{name}: ”{term}” saknas i instruktionen för första öppningen")

    def test_permission_steps_use_the_same_names_everywhere(self):
        message = RECORDER[RECORDER.index("case .permissionDenied:"):RECORDER.index("case .startFailed")]
        for name, text in (("site", plain(SITE)), ("README", plain(README)), ("appen", message)):
            for term in PERMISSION + RESET:
                self.assertIn(term, text, f"{name}: ”{term}” saknas i instruktionen för mötesinspelning")

    def test_app_message_has_numbered_steps(self):
        message = RECORDER[RECORDER.index("case .permissionDenied:"):RECORDER.index("case .startFailed")]
        for n in ("1.", "2.", "3."):
            self.assertIn(n, message)

    def test_site_says_what_you_see_when_it_worked(self):
        ok = re.findall(r'class="ok"', SITE)
        self.assertGreaterEqual(len(ok), 4, "varje installations- och behörighetssteg ska säga vad man ser när det lyckats")

    def test_site_has_permission_section_and_link_to_it(self):
        self.assertIn('id="motesinspelning"', SITE)
        self.assertIn('href="#motesinspelning"', SITE)

    def test_recording_success_text_matches_the_app(self):
        controls = (ROOT / "Transkribera" / "Views" / "Home" / "MeetingControls.swift").read_text(encoding="utf-8")
        for label in ("Starta inspelning", "Stoppa inspelning", "Spelar in"):
            self.assertIn(f'"{label}"', controls, f"appen har ingen knapp/text ”{label}” längre; uppdatera instruktionerna")
            self.assertIn(label, plain(SITE) + plain(README))


if __name__ == "__main__":
    unittest.main()
