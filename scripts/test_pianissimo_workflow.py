"""Kontroll: modellbygget för Pianissimo får aldrig skriva över en publicerad modell.

Appen laddar ner pianissimo-sv.zip ur releasen pianissimo-v1. Testvarianten med kodaren i
16 bitar (pianissimo-sv-fp16.zip, 2026-11-13) byggs i samma arbetsflöde; bara en variant
som saknas får laddas upp, så att kollegornas modell inte byts ut av ett test.
Kör: python3 -m unittest discover -s scripts"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = (ROOT / ".github/workflows/pianissimo-model.yml").read_text(encoding="utf-8")
FINISH = (ROOT / "scripts/pianissimo/finish.py").read_text(encoding="utf-8")


class PianissimoWorkflowTests(unittest.TestCase):
    def test_published_models_are_never_overwritten(self):
        for line in WORKFLOW.splitlines():
            if "gh release upload" in line and ("$ASSET" in line or "$FP16_ASSET" in line):
                self.assertNotIn("--clobber", line, line.strip())

    def test_each_variant_is_built_only_when_missing(self):
        self.assertIn("needs.check.outputs.int8 == 'true'", WORKFLOW)
        self.assertIn("needs.check.outputs.fp16 == 'true'", WORKFLOW)

    def test_fp16_variant_keeps_the_encoder_unquantized(self):
        self.assertIn('--encoder fp16', WORKFLOW)
        self.assertRegex(FINISH, r'if name == "Encoder" and args\.encoder == "int8"')
        # Mappen i zip:en ska heta som modellen i appen (WhisperModel.pianissimoFP16).
        catalog = (ROOT / "Transkribera/Models/ModelCatalog.swift").read_text(encoding="utf-8")
        name = re.search(r'case pianissimoFP16 = "([^"]+)"', catalog).group(1)
        self.assertIn(f"FP16_NAME: {name}", WORKFLOW)
        self.assertIn(f"FP16_ASSET: {name}.zip", WORKFLOW)


if __name__ == "__main__":
    unittest.main()
