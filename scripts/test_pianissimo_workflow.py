"""Kontroll: modellbygget för Pianissimo får aldrig skriva över en publicerad modell.

Appen laddar ner pianissimo-sv.zip ur releasen pianissimo-v1. Testvarianterna i 16 och
32 bitar (pianissimo-sv-fp16.zip, pianissimo-sv-fp32.zip, 2026-11-13) byggs i samma
arbetsflöde; bara en variant som saknas får laddas upp, så att kollegornas modell inte
byts ut av ett test.
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
            if "gh release upload" in line and any(f"${name}" in line for name in ("ASSET", "FP16_ASSET", "FP32_ASSET")):
                self.assertNotIn("--clobber", line, line.strip())

    def test_each_variant_is_built_only_when_missing(self):
        self.assertIn("needs.check.outputs.int8 == 'true'", WORKFLOW)
        self.assertIn("needs.check.outputs.fp16 == 'true'", WORKFLOW)
        self.assertIn("needs.check.outputs.fp32 == 'true'", WORKFLOW)

    def test_test_variants_keep_the_encoder_unquantized(self):
        self.assertEqual(WORKFLOW.count("--encoder original"), 2)
        self.assertRegex(FINISH, r'if name == "Encoder" and args\.encoder == "int8"')
        self.assertIn("--precision FLOAT32", WORKFLOW)

    def test_zip_folders_are_named_like_the_models_in_the_app(self):
        catalog = (ROOT / "Transkribera/Models/ModelCatalog.swift").read_text(encoding="utf-8")
        for case, key in (("pianissimoFP16", "FP16"), ("pianissimoFP32", "FP32")):
            name = re.search(rf'case {case} = "([^"]+)"', catalog).group(1)
            self.assertIn(f"{key}_NAME: {name}", WORKFLOW)
            self.assertIn(f"{key}_ASSET: {name}.zip", WORKFLOW)


if __name__ == "__main__":
    unittest.main()
