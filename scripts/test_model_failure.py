"""Kontroll: när Core ML inte kan köra en modell (MacBook Air M1, 8 GB, 2026-11-08) ska
felet finnas kvar, gå att kopiera, säga vilket steg det hände i, och appen ska ha försökt
på processorn och frigjort minne innan den ger upp.
Kör: python3 -m unittest discover -s scripts"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERVICE = (ROOT / "Transkribera" / "Services" / "TranscriberService.swift").read_text(encoding="utf-8")
PARAKEET = (ROOT / "Transkribera" / "Services" / "ParakeetTranscriber.swift").read_text(encoding="utf-8")
DETAIL = (ROOT / "Transkribera" / "Views" / "Detail" / "TranscriptDetailView.swift").read_text(encoding="utf-8")
LOG = (ROOT / "Transkribera" / "Services" / "ErrorLog.swift").read_text(encoding="utf-8")


class ModelFailureTests(unittest.TestCase):
    def test_every_failure_goes_through_fail_and_is_logged(self):
        # Ingen catch får sätta .failed direkt med den råa texten: då försvinner steget och loggen.
        self.assertNotRegex(SERVICE, r"phase = \.failed\(error\.localizedDescription\)")
        self.assertIn("ErrorLog.append(model: model.displayName, step: step", SERVICE)
        self.assertGreaterEqual(len(re.findall(r"throw fail\(error, model:", SERVICE)), 3)

    def test_every_model_retries_once_without_neural_engine(self):
        # Nicklas M1: ANEProgramProcessRequestDirect() Failed status=0xf, sedan E5RT-fel.
        self.assertIn("configuration.computeUnits = .cpuAndGPU", PARAKEET)
        self.assertIn("avoidsNeuralEngine: avoidsNeuralEngine", SERVICE)
        self.assertIn("computeOptions: avoidsNeuralEngine", SERVICE)
        self.assertIn("embedderModelInfo: .embedder(computeUnits: Self.speakerKitWithoutNeuralEngine)", SERVICE)
        self.assertIn("computeUnits: avoidsNeuralEngine ? Self.withoutNeuralEngine : .all", SERVICE)
        # Pianissimo, Whisper, talarsteget, "Fånga korta svar" och korskollen med KB Large har
        # var sitt nytt försök.
        self.assertEqual(len(re.findall(r"catch let error where canRetryWithoutNeuralEngine\(error\)", SERVICE)), 5)
        self.assertIn("!avoidsNeuralEngine && FailureExplainer.isModelComputeFailure", SERVICE)

    def test_nemotron_failure_is_logged_not_swallowed(self):
        self.assertNotIn("try? await shortReplyDiarizer.turns", SERVICE)
        self.assertIn('ErrorLog.append(model: "Nemotron 3"', SERVICE)

    def test_low_memory_runs_one_model_at_a_time(self):
        speakers = SERVICE[SERVICE.index("} else if options.identifySpeakers {"):]
        before = speakers[:speakers.index("phase = .identifyingSpeakers")]
        self.assertIn("if Self.hasLowMemory { await releaseRecognitionModel() }", before)
        self.assertIn("if Self.hasLowMemory { await releaseSpeakerModels() }", speakers)

    def test_failed_view_keeps_error_copyable_and_offers_redownload(self):
        failed = DETAIL[DETAIL.index('Label("Transkriberingen misslyckades"'):]
        failed = failed[:failed.index("default:")]
        self.assertIn(".textSelection(.enabled)", failed)
        self.assertIn('"Kopiera felinformation"', failed)
        self.assertIn('"Ladda ned modellen igen"', failed)

    def test_log_never_contains_transcript_text(self):
        # Loggen får bara ta emot steg och teknisk text, aldrig segment eller liveText.
        self.assertNotIn("segments", LOG)
        self.assertNotIn("liveText", LOG)


if __name__ == "__main__":
    unittest.main()


class SpeakerStepDeadlineTests(unittest.TestCase):
    """Talarsteget hängde sig tyst på MacBook Air M1 (2026-11-08): ingen rad i Felloggen, och vyn stod still."""

    def test_both_speaker_models_have_a_deadline_and_log_their_steps(self):
        fn = SERVICE[SERVICE.index("func speakerTurns("):SERVICE.index("private func saveSpeakerTurns")]
        self.assertEqual(fn.count("Deadline.run(seconds: limit)"), 2, "Nemotron och SpeakerKit ska ha var sin tidsgräns")
        for text in ("Info: Nemotron 3 startar", "Info: SpeakerKit startar", "Tidsgräns: Nemotron 3", "Tidsgräns: SpeakerKit"):
            self.assertIn(text, fn)
        self.assertIn("throw SpeakerStepTimedOut", fn)
        self.assertIn("nemotronStalled = true", fn)
        self.assertIn("catch is CancellationError", fn, "Avbryt får inte bli ett byte till SpeakerKit")

    def test_a_timed_out_speaker_step_still_gives_the_text_with_a_visible_notice(self):
        self.assertIn("catch let timeout as SpeakerStepTimedOut", SERVICE)
        self.assertIn("notice: notice", SERVICE)
        queue = (ROOT / "Transkribera" / "Services" / "TranscriptionQueue.swift").read_text(encoding="utf-8")
        self.assertIn(": output.notice", queue)
        detail = (ROOT / "Transkribera" / "Views" / "Detail" / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        self.assertIn("completionNoticeRow", detail)


class SpeakerKitCpuOnlyTests(unittest.TestCase):
    """SpeakerKit svarade aldrig på .cpuAndGPU på MacBook Air M1, macOS 14 (2026-11-08)."""

    def test_speakerkit_runs_on_the_cpu_only_without_neural_engine(self):
        self.assertIn("static let speakerKitWithoutNeuralEngine: MLComputeUnits = .cpuOnly", SERVICE)

    def test_speakerkit_progress_is_logged(self):
        fn = SERVICE[SERVICE.index("private func speakerKitTurns"):]
        self.assertIn("progress.report(update.fractionCompleted)", fn)
        self.assertIn("Info: SpeakerKit", SERVICE)
