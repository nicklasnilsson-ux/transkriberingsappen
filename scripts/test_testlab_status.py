"""Kontroll: Testlabbet visar vad som händer under en körning, och tider under en minut.

2026-11-13: körningen med Pianissimo i 32 bitar laddade ner 2,3 GB utan att det syntes
(bara "Körning 3 av 3"), och korta körningar visades som "0 min".
Kör: python3 -m unittest discover -s scripts"""
import unittest
from pathlib import Path

VIEW = (Path(__file__).resolve().parent.parent / "Transkribera/Views/TestLab/TestLabView.swift").read_text(encoding="utf-8")


class TestLabStatusTests(unittest.TestCase):
    def test_live_phase_is_shown(self):
        self.assertIn("queue.transcriber.statusText", VIEW)

    def test_short_runs_show_seconds(self):
        self.assertIn("TimeFormatting.duration(seconds)", VIEW)
        self.assertNotIn('(seconds / 60).rounded())) min"', VIEW)


if __name__ == "__main__":
    unittest.main()
