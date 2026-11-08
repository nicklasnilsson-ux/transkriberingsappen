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
        self.assertIn("embedderModelInfo: .embedder(computeUnits: Self.withoutNeuralEngine)", SERVICE)
        self.assertIn("computeUnits: avoidsNeuralEngine ? Self.withoutNeuralEngine : .all", SERVICE)
        # Pianissimo, Whisper och talarsteget har var sitt nytt försök.
        self.assertEqual(len(re.findall(r"catch let error where canRetryWithoutNeuralEngine\(error\)", SERVICE)), 3)
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
