"""Kontroll: talare som inte är intervjuare heter "Talare 1", "Talare 2" …, inte "Kund"
(Nicklas 2026-11-10: "Talare är en mer öppen beskrivning"). Ordet får inte komma tillbaka
i appens texter (strängar i Swift-koden; kommentarer räknas inte), landningssidan eller README. Rader som bara finns för äldre transkriberingar
(där övriga talare hette "Kund N" före 0.9.35) märks med kommentaren `kund-ok`.
Kör: python3 -m unittest discover -s scripts"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORD = re.compile(r"\bkund(?:er|erna|en|ens|ernas)?\b", re.IGNORECASE)
ALLOW = "kund-ok"
# Swift-strängar, även #"..."#. Kommentarer om kunder i allmänhet får finnas.
STRING = re.compile(r'#?"(?:[^"\\]|\\.)*"#?')


def files():
    yield from (ROOT / "Transkribera").rglob("*.swift")
    for package in (ROOT / "Packages").iterdir():
        yield from (package / "Sources").rglob("*.swift")
    yield from (ROOT / "site").rglob("*.html")
    yield ROOT / "README.md"


def hits():
    found = []
    for path in files():
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if path.suffix == ".swift":
                if line.lstrip().startswith("//"):
                    continue
                checked = " ".join(STRING.findall(line))
            else:
                checked = line
            if WORD.search(checked) and ALLOW not in line:
                found.append(f"{path.relative_to(ROOT)}:{number}: {line.strip()}")
    return found


class NoKundTests(unittest.TestCase):
    def test_kund_is_not_used(self):
        found = hits()
        self.assertEqual(found, [], "Använd \"Talare N\" i stället för \"Kund\" (eller märk en rad för äldre data med kund-ok):\n" + "\n".join(found))

    def test_pattern_catches_the_role_but_not_kunde(self):
        self.assertTrue(WORD.search('names[speaker] = "Kund 1"'))
        self.assertTrue(WORD.search("övriga blir kunder"))
        self.assertFalse(WORD.search('"Kunde inte spara"'))
        self.assertFalse(WORD.search("kundsvar"))

    def test_only_strings_are_checked_in_swift(self):
        self.assertEqual(STRING.findall('x = "Kund 1" // kunder'), ['"Kund 1"'])
        self.assertEqual(STRING.findall('of: #"^(?:kund)$"#,'), ['#"^(?:kund)$"#'])

    def test_role_code_uses_talare(self):
        roles = (ROOT / "Packages/TranskriberaCore/Sources/TranskriberaCore/SpeakerRoles.swift").read_text(encoding="utf-8")
        self.assertIn('public static let speakerPrefix = "Talare"', roles)
        self.assertIn('"\\(speakerPrefix) \\(next)"', roles)


if __name__ == "__main__":
    unittest.main()
