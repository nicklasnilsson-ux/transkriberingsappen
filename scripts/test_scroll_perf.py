"""Kontroll mot att långa transkriberingar fryser vid scrollning (v0.9.7: "wheel of death", appen
"svarar inte" på 101 % CPU). Orsak: transkriptionsvyns body läste uppspelningstiden, som tickar 10
gånger i sekunden, och räknade då om hela texten (sortering, anonymiseringsjämförelse, styckeindelning)
och ritade om alla synliga stycken. Kontrollerar källkoden, eftersom prestanda inte kan mätas i CI.
Kör: python3 -m unittest discover -s scripts"""
import re
import unittest
from pathlib import Path

DETAIL = Path(__file__).resolve().parent.parent / "Transkribera" / "Views" / "Detail"


class ScrollPerformanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = (DETAIL / "TranscriptDetailView.swift").read_text(encoding="utf-8")
        cls.paragraph = (DETAIL / "ParagraphRow.swift").read_text(encoding="utf-8")
        cls.segment = (DETAIL / "SegmentRow.swift").read_text(encoding="utf-8")

    def test_playback_time_is_only_read_inside_playback_time_reader(self):
        # Alla läsningar av tiden ska ligga i en PlaybackTimeReader-closure (eller i läsaren själv).
        start = self.text.index("struct PlaybackTimeReader")
        reader = self.text[start:self.text.index("\n}\n", start)]
        outside = self.text.replace(reader, "")
        reads = [m.start() for m in re.finditer(r"\bplayer\??\.currentTime\b", outside)]
        self.assertEqual(reads, [], "Vyn läser player.currentTime utanför PlaybackTimeReader: hela vyn räknas då om 10 gånger i sekunden")
        self.assertGreaterEqual(self.text.count("PlaybackTimeReader(player:"), 3, "Tid, reglage och text läses via läsaren")

    def test_rows_skip_redraw_when_only_time_ticks(self):
        for row, source in (("ParagraphRow", self.paragraph), ("SegmentRow", self.segment)):
            self.assertIn(f"extension {row}: Equatable", source)
            call = self.text[self.text.index(f"{row}("):]
            self.assertIn(".equatable()", call[:call.index(".id(")], f"{row} ska ha .equatable()")
        self.assertIn("currentTime: isActiveParagraph ? currentTime : nil", self.text)
        self.assertIn("currentTime: segment.persistentModelID == activeID ? currentTime : nil", self.text)

    def test_text_rows_do_not_rebuild_paragraphs_per_tick(self):
        # Styckeindelningen görs utanför PlaybackTimeReader, inte i tidsclosuren.
        reader_call = self.text[self.text.index("PlaybackTimeReader(player: player) { currentTime in"):]
        reader_call = reader_call[:re.search(r"\} else (if |\{)", reader_call).start()]
        self.assertNotIn("Self.paragraphs(", reader_call)
        self.assertNotIn("sortedSegments", reader_call)

    def test_body_does_not_build_all_rows_without_lazy_stack(self):
        self.assertGreaterEqual(self.text.count("LazyVStack"), 2)


if __name__ == "__main__":
    unittest.main()
