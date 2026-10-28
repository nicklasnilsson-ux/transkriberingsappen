"""Tester för changelog.py och upgrade_store.py. Kör: python3 -m unittest discover -s scripts"""
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import changelog  # noqa: E402
import upgrade_store  # noqa: E402

SAMPLE = """# Ändringslogg

## [Kommande]
- Något nytt.

## [0.4.2] – 2026-10-28
### Rättat
- Startar igen.

## [0.4.1] – 2026-10-28
- Äldre.
"""


class ChangelogTests(unittest.TestCase):
    def test_section_stops_at_next_heading(self):
        self.assertEqual(changelog.section(SAMPLE, "0.4.2"), "### Rättat\n- Startar igen.")

    def test_last_section(self):
        self.assertEqual(changelog.section(SAMPLE, "0.4.1"), "- Äldre.")

    def test_missing_version(self):
        self.assertIsNone(changelog.section(SAMPLE, "0.5.0"))
        self.assertIsNone(changelog.section(SAMPLE, "0.4"))

    def test_check_fails_without_section(self):
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as f:
            f.write(SAMPLE)
        env = {**os.environ, "CHANGELOG": f.name}
        ok = subprocess.run([sys.executable, HERE / "changelog.py", "check", "0.4.2"], env=env, capture_output=True)
        bad = subprocess.run([sys.executable, HERE / "changelog.py", "check", "0.5.0"], env=env, capture_output=True)
        self.assertEqual(ok.returncode, 0)
        self.assertNotEqual(bad.returncode, 0)

    def test_repository_changelog_has_every_released_version(self):
        text = (HERE.parent / "CHANGELOG.md").read_text(encoding="utf-8")
        for version in ["0.1.0", "0.2.0", "0.3.0", "0.4.0", "0.4.1", "0.4.2"]:
            self.assertTrue(changelog.section(text, version), version)


def core_data_store(path: str) -> None:
    """Samma tabeller som SwiftData skapar för Transcript och TranscriptSegment."""
    db = sqlite3.connect(path)
    db.executescript("""
        CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR, Z_SUPER INTEGER, Z_MAX INTEGER);
        INSERT INTO Z_PRIMARYKEY VALUES (1, 'Transcript', 0, 0), (2, 'TranscriptSegment', 0, 0);
        CREATE TABLE ZTRANSCRIPT (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZISRECORDING INTEGER,
            ZISVIDEO INTEGER, ZCREATEDAT TIMESTAMP, ZDURATION FLOAT, ZERRORMESSAGE VARCHAR, ZLANGUAGE VARCHAR,
            ZMEDIAFILENAME VARCHAR, ZMODELNAME VARCHAR, ZORIGINALFILENAME VARCHAR, ZSTATUSRAW VARCHAR,
            ZTITLE VARCHAR, ZID BLOB);
        CREATE TABLE ZTRANSCRIPTSEGMENT (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZINDEX INTEGER,
            ZTRANSCRIPT INTEGER, ZEND FLOAT, ZSTART FLOAT, ZSPEAKER VARCHAR, ZTEXT VARCHAR, ZWORDSDATA BLOB);
    """)
    db.commit()


class UpgradeStoreTests(unittest.TestCase):
    def setUp(self):
        self.store = str(Path(tempfile.mkdtemp()) / "Transkribera.store")
        core_data_store(self.store)

    def test_seed_then_check(self):
        upgrade_store.seed(self.store)
        upgrade_store.check(self.store)
        db = sqlite3.connect(self.store)
        self.assertEqual(db.execute("SELECT Z_MAX FROM Z_PRIMARYKEY ORDER BY Z_ENT").fetchall(), [(1,), (2,)])

    def test_check_detects_lost_segment(self):
        upgrade_store.seed(self.store)
        db = sqlite3.connect(self.store)
        db.execute("DELETE FROM ZTRANSCRIPTSEGMENT WHERE ZINDEX = 1")
        db.commit()
        with self.assertRaises(SystemExit):
            upgrade_store.check(self.store)

    def test_check_detects_lost_transcript(self):
        with self.assertRaises(SystemExit):
            upgrade_store.check(self.store)


if __name__ == "__main__":
    unittest.main()
