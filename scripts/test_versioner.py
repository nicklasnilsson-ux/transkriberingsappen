"""Kontroll: sparade versioner av texten (0.8.0). Reglerna själva (de 4 senaste, den äldsta
raderas, aldrig den nya) är enhetstestade i VersionHistoryTests. Här kontrolleras att appen
använder dem och att databasen migreras.
Kör: python3 -m unittest discover -s scripts"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "Transkribera"


def read(rel):
    return (APP / rel).read_text(encoding="utf-8")


class VersionTests(unittest.TestCase):
    def test_text_is_only_replaced_through_the_version_functions(self):
        # Ett direkt anrop skulle skriva över texten utan att spara den förra versionen.
        callers = []
        for path in APP.rglob("*.swift"):
            for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if "replaceSegments(" in line and "func replaceSegments" not in line:
                    callers.append(f"{path.name}:{n}")
        self.assertEqual(sorted(c.split(":")[0] for c in callers), ["TranscriptVersion.swift", "TranscriptVersion.swift"], callers)

    def test_queue_saves_the_new_version_only_when_the_run_succeeded(self):
        queue = read("Services/TranscriptionQueue.swift")
        self.assertIn("addNewVersion(", queue)
        process = queue[queue.index("private func process("):]
        success = process[process.index("let output = try await wait.wait(for: job)"):process.index("} catch is CancellationError")]
        self.assertIn("addNewVersion(", success)
        # Modellen som texten gjordes med återställs när körningen avbryts eller misslyckas.
        self.assertEqual(process.count("transcript.modelName = previousModelName"), 2)

    def test_old_versions_are_dropped_with_the_tested_rule(self):
        text = read("Models/TranscriptVersion.swift")
        self.assertIn("VersionHistory.idsToDrop(", text)

    def test_database_is_migrated_from_a_frozen_schema_1(self):
        db = read("Models/Database.swift")
        self.assertIn("SchemaV1.Transcript.self", db)  # V1 är nedkopierade modeller, inte de levande
        self.assertIn("enum SchemaV2", db)
        self.assertIn(".lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)", db)
        self.assertIn("Schema(versionedSchema: SchemaV2.self)", db)
        self.assertIn("TranscriptVersion.self", db)

    def test_new_stored_fields_exist_in_the_live_models(self):
        text = read("Models/Transcript.swift")
        self.assertIn("var versionDate: Date?", text)  # nytt fält måste vara valfritt (lätt migrering)
        self.assertRegex(text, r"var versions: \[TranscriptVersion\] = \[\]")

    def test_dialog_cannot_be_turned_off_when_something_is_deleted(self):
        # Reglerna ligger i Core (enhetstestade); vyerna ska fråga via dem, inte via egna villkor.
        for name in ("Detail/TranscriptDetailView.swift", "Sidebar/SidebarView.swift"):
            self.assertIn("RetranscribeDialog.needsDialog(", read("Views/" + name), name)

    def test_version_picker_sits_first_in_the_header_and_older_versions_say_so(self):
        text = read("Views/Detail/TranscriptDetailView.swift")
        header = text[text.index("private var headerRow"):text.index("private var toolsRow")]
        self.assertIn("versionPicker", header)
        strip = text[text.index("private var olderVersionStrip"):][:900]
        self.assertIn("isViewingOlderVersion", strip)
        self.assertIn("äldre version", strip)

    def test_title_card_date_is_the_shown_versions_not_the_first_transcription(self):
        # Felet 0.8.0: raden visade createdAt (första transkriberingen) även när en annan version visades.
        detail = read("Views/Detail/TranscriptDetailView.swift")
        self.assertNotIn("createdAt", detail)
        meta = detail[detail.index("private var metaLine"):detail.index("private var layoutPicker")]
        self.assertIn("transcript.liveVersionDate.formatted(", meta)
        model = read("Models/TranscriptVersion.swift")
        self.assertIn("VersionHistory.shownDate(versionDate: versionDate, createdAt: createdAt)", model)
        # Märket upprepar inte klockslaget som datumet bredvid redan har.
        picker = detail[detail.index("private var versionPicker"):detail.index("private func versionMenuTitle")]
        self.assertIn("versionShortLabel", picker)
        self.assertNotIn("versionLabel", picker)

    def test_rerun_settings_are_one_pill_with_one_popover(self):
        detail = read("Views/Detail/TranscriptDetailView.swift")
        self.assertEqual(detail.count("RerunSettingsPopover("), 1)
        self.assertEqual(detail.count("showRerunSettings = true"), 1)
        self.assertNotIn("settingsChip(", detail)

    def test_ask_setting_exists_with_the_same_default_in_both_places(self):
        for rel in ("Views/Settings/SettingsView.swift", "Views/Detail/RetranscribeSheet.swift"):
            self.assertRegex(read(rel), r"SettingsKey\.askBeforeRetranscribe\)\s+private var \w+\s*=\s*true", rel)


if __name__ == "__main__":
    unittest.main()
