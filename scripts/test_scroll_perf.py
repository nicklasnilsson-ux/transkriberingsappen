"""Kontroll mot att långa transkriberingar fryser eller hackar vid scrollning.

v0.9.7: "wheel of death" (101 % CPU). Transkriptionsvyns body läste uppspelningstiden, som tickar 10
gånger i sekunden, och räknade då om hela texten och ritade om alla synliga stycken.
v0.9.25: segt och hoppigt att skrolla under uppspelning, med och utan "Följ uppspelning". Listan
(LazyVStack med alla stycken) låg fortfarande i tidsclosuren och byggdes om vid varje tick, det
spelade stycket ritades om helt vid varje tick, och "Följ uppspelning" drog tillbaka texten medan
man skrollade. Kontrollerar källkoden, eftersom prestanda inte kan mätas i CI.
Kör: python3 -m unittest discover -s scripts"""
import re
import unittest
from pathlib import Path

DETAIL = Path(__file__).resolve().parent.parent / "Transkribera" / "Views" / "Detail"


def reader_closures(source):
    """Innehållet i varje `PlaybackTimeReader(...) { ... }`-closure i källkoden."""
    result = []
    for match in re.finditer(r"PlaybackTimeReader\(player: [^)]*\) \{", source):
        depth, i = 1, match.end()
        while depth:
            depth += {"{": 1, "}": -1}.get(source[i], 0)
            i += 1
        result.append(source[match.end():i - 1])
    return result


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
        bar = (DETAIL.parent / "Player" / "PlayerBar.swift").read_text(encoding="utf-8")
        self.assertEqual(re.findall(r"\bplayer\??\.currentTime\b", bar), [], "Spelarraden läser tiden via PlaybackTimeReader")
        self.assertGreaterEqual(self.text.count("PlaybackTimeReader(player:"), 1, "Texten läser tiden via läsaren")
        self.assertGreaterEqual(bar.count("PlaybackTimeReader(player:"), 2, "Tid och reglage läses via läsaren")

    def test_rows_skip_redraw_when_only_time_ticks(self):
        for row, source in (("ParagraphRow", self.paragraph), ("SegmentRow", self.segment)):
            self.assertIn(f"extension {row}: Equatable", source)
            call = self.text[self.text.index(f"{row}("):]
            self.assertIn(".equatable()", call[:call.index(".id(")], f"{row} ska ha .equatable()")
        # Bara det spelade stycket får spelaren (och läser då själv tiden i texten).
        self.assertIn("clock: isActiveParagraph ? player : nil", self.text)
        self.assertIn("clock: segment.persistentModelID == activeID ? player : nil", self.text)
        for row, source in (("ParagraphRow", self.paragraph), ("SegmentRow", self.segment)):
            self.assertIn("l.clock === r.clock", source, f"{row} ska jämföra spelaren")
            self.assertNotIn("let currentTime", source, f"{row} ska inte få tiden: då ritas hela stycket om vid varje tick")

    def test_list_is_not_rebuilt_per_tick(self):
        # Ingen tidsclosure i transkriptionsvyn får bygga listan; den byggs i PlaybackFocusReader,
        # som bara ändras när nästa segment börjar.
        for closure in reader_closures(self.text):
            for forbidden in ("paragraphRows(", "segmentRows(", "ForEach", "LazyVStack", "Self.paragraphs(", "sortedSegments"):
                self.assertNotIn(forbidden, closure, f"Listan byggs om vid varje tick ({forbidden} i PlaybackTimeReader)")
        self.assertIn("PlaybackFocusReader(focus: playbackFocus) { activeID in", self.text)
        self.assertIn("PlaybackFocusTracker(player: player", self.text)
        # PlaybackFocus skriver bara när segmentet byts (annars ritas listan om ändå).
        focus = self.text[self.text.index("final class PlaybackFocus"):]
        self.assertIn("if id != activeID { activeID = id }", focus[:focus.index("\n}\n")])

    def test_only_the_text_reads_time_inside_rows(self):
        # I raderna läser bara texten tiden, och den jämförs (equatable) så att den ritas om först
        # när nästa ord markeras.
        for row, source in (("ParagraphRow", self.paragraph), ("SegmentRow", self.segment)):
            closures = reader_closures(source)
            self.assertEqual(len(closures), 1, f"{row} ska läsa tiden på ett ställe")
            closure = closures[0]
            self.assertIn("ReadingText(", closure)
            self.assertIn(".equatable()", closure)
            for forbidden in ("Header", "headerLine", "RowEditActions", "SpeakerLabel", "TimecodeButton"):
                self.assertNotIn(forbidden, closure, f"{row}: {forbidden} ritas om vid varje tick")
        self.assertIn("struct ReadingText: View, Equatable", self.paragraph)

    def test_follow_waits_while_user_scrolls(self):
        follow = self.text[self.text.index("private func follow("):]
        follow = follow[:follow.index("\n    }\n")]
        self.assertIn("scrollAnchor.userScrolledRecently()", follow, "Följ uppspelning drar tillbaka texten medan man skrollar")
        observer = (DETAIL / "ScrollOffsetObserver.swift").read_text(encoding="utf-8")
        self.assertIn("addLocalMonitorForEvents(matching: .scrollWheel)", observer)
        self.assertIn("willStartLiveScrollNotification", observer)
        self.assertIn("NSEvent.removeMonitor", observer)

    def test_rows_do_no_work_per_scroll_step(self):
        # 0.9.33: RowFrameReporter var en GeometryReader med onChange per rad, som skrev radens läge
        # vid varje skrollsteg. Läget läses nu först när det behövs (ScrollAnchor.rowTops).
        observer = (DETAIL / "ScrollOffsetObserver.swift").read_text(encoding="utf-8")
        reporter = observer[observer.index("struct RowFrameReporter"):]
        for forbidden in ("GeometryReader", "onChange", "onAppear", "geo.frame"):
            self.assertNotIn(forbidden, reporter, f"Raderna gör arbete vid varje skrollsteg ({forbidden})")
        self.assertIn("var rowTops: [AnyHashable: CGFloat] {", observer, "rowTops ska räknas vid behov, inte lagras")

    def test_body_does_not_build_all_rows_without_lazy_stack(self):
        self.assertGreaterEqual(self.text.count("LazyVStack"), 2)


if __name__ == "__main__":
    unittest.main()
