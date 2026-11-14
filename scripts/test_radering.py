#!/usr/bin/env python3
"""Kontrollerar att varje väg att radera en transkribering också städar bort spåren av texten.

Raderar man en fil ska texten inte gå att nå (GDPR): databasens säkerhetskopior ska tas bort och
databasfilen packas om. En körning som pågår när filen raderas får inte skriva tillbaka text.
Kör: python3 scripts/test_radering.py
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QUEUE = (ROOT / "Transkribera/Services/TranscriptionQueue.swift").read_text(encoding="utf-8")
DATABASE = (ROOT / "Transkribera/Models/Database.swift").read_text(encoding="utf-8")


def body(source: str, signature: str) -> str:
    start = source.index(signature)
    brace = source.index("{", start)
    depth = 0
    for i in range(brace, len(source)):
        depth += {"{": 1, "}": -1}.get(source[i], 0)
        if depth == 0:
            return source[brace:i]
    raise AssertionError(signature)


class DeletionTests(unittest.TestCase):
    def test_every_public_delete_erases_traces(self):
        for signature in ("func delete(_ transcripts: [Transcript]", "func delete(_ transcript: Transcript)"):
            self.assertIn("Database.eraseTracesOfDeletedText()", body(QUEUE, signature), signature)

    def test_only_one_place_deletes_transcripts_from_the_context(self):
        deletes = re.findall(r"context\.delete\(transcript\)", QUEUE)
        self.assertEqual(len(deletes), 1, "all radering ska gå via remove(_:)")
        self.assertIn("context.delete(transcript)", body(QUEUE, "private func remove("))

    def test_running_job_cannot_write_back_after_delete(self):
        process = body(QUEUE, "private func process(")
        self.assertGreaterEqual(process.count("finishIfDeleted(id)"), 3)
        self.assertIn("deletedIDs.insert", body(QUEUE, "private func remove("))

    def test_cleanup_removes_backups_and_compacts(self):
        cleanup = body(DATABASE, "static func eraseTracesOfDeletedText()")
        self.assertIn("eraseBackups", cleanup)
        self.assertIn("compact", cleanup)
        compact = body(DATABASE, "static func compact(")
        for sql in ("secure_delete", "VACUUM", "wal_checkpoint(TRUNCATE)"):
            self.assertIn(sql, compact)


if __name__ == "__main__":
    unittest.main()
