"""Appen har bara tre textstorlekar: 12, 14 och 16 pt (Nicklas 2026-11-06).

Före 0.9.12 fanns sju storlekar i gränssnittet (10, 11, 12, 13, 15, 17 och 44 pt), och
hjälptexter och tidskoder var 10 pt. Kontrollen stoppar att en ny storlek smyger sig in:
- inga av systemets textstilar (.caption, .callout, .body, .headline, .title …), de har egna storlekar
- inga fasta storlekar (.system(size:), NSFont.systemFont(ofSize:)) utanför Theme.swift
- Theme.swift har exakt storlekarna 12/14/16, plus läsytan och mötestimern som enda undantag
- varje fönster, ark och popover har 14 pt som standard (annars blir texten systemets 13 pt)
- varje ark och popover har .presentationRoot(): 14 pt och ingen radgräns som ärvs från det den öppnas
  från (modellväljarens texter klipptes med … från sidopanelens Inställningar-kort, 2026-11-06)
- små knappar (controlSize .small/.mini, 11 pt) har en av appens storlekar

Kör: python3 -m unittest discover -s scripts"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "Transkribera"
THEME = APP / "Views" / "Theme.swift"

TEXT_STYLES = r"(largeTitle|title|title2|title3|headline|subheadline|body|callout|footnote|caption|caption2)"
# En textstil i ett typsnittssammanhang: .font(.caption), font: .callout.weight(...), Font.body, .system(.caption, ...)
STYLE_USE = re.compile(
    r"(\.font\(\s*\.|Font\s*=\s*\.|font:\s*\.|Font\.|\.system\(\s*\.)" + TEXT_STYLES + r"\b"
)
FIXED_SIZE = re.compile(r"\.system\(\s*size:|systemFont\(\s*ofSize:|NSFont\(\s*name:|\.custom\(")
SMALL_CONTROL = re.compile(r"\.controlSize\(\s*\.(small|mini)\s*\)")


def swift_files():
    return sorted(APP.rglob("*.swift"))


def style_violations(text):
    """Rader som använder en av systemets textstilar."""
    return [n for n, line in enumerate(text.split("\n"), 1) if STYLE_USE.search(line.split("//")[0])]


def fixed_size_violations(text):
    """Rader med en fast storlek (tillåts bara i Theme.swift)."""
    return [n for n, line in enumerate(text.split("\n"), 1) if FIXED_SIZE.search(line.split("//")[0])]


def small_control_violations(text):
    """Små kontroller med text måste ha en av appens storlekar inom tre rader (ProgressView har ingen text)."""
    lines = text.split("\n")
    bad = []
    for i, line in enumerate(lines):
        if not SMALL_CONTROL.search(line) or "ProgressView" in line:
            continue
        # Modifierare på en ProgressView några rader upp (ProgressView(value:)\n.progressViewStyle\n.controlSize)
        if any(l.strip().startswith("ProgressView") for l in lines[max(0, i - 3): i]):
            continue
        window = "\n".join(lines[max(0, i - 3): i + 4])
        if ".font(.app(" not in window:
            bad.append(i + 1)
    return bad


def presentations_without_font(text):
    """.sheet/.popover vars innehåll saknar .presentationRoot() (14 pt och nollställd radgräns)."""
    lines = text.split("\n")
    bad = []
    for i, line in enumerate(lines):
        if not re.search(r"\.(sheet|popover)\(", line):
            continue
        depth, body = 0, []
        for j in range(i, len(lines)):
            depth += lines[j].count("{") - lines[j].count("}")
            body.append(lines[j])
            if depth == 0 and "{" in "".join(body):
                break
        if ".presentationRoot()" not in "\n".join(body):
            bad.append(i + 1)
    return bad


class TextSizeTests(unittest.TestCase):
    def test_no_system_text_styles(self):
        found = {}
        for path in swift_files():
            lines = style_violations(path.read_text(encoding="utf-8"))
            if lines:
                found[str(path.relative_to(ROOT))] = lines
        self.assertEqual(found, {}, "Använd .app(.small/.regular/.large) i stället för systemets textstilar")

    def test_no_fixed_sizes_outside_theme(self):
        found = {}
        for path in swift_files():
            if path == THEME:
                continue
            lines = fixed_size_violations(path.read_text(encoding="utf-8"))
            if lines:
                found[str(path.relative_to(ROOT))] = lines
        self.assertEqual(found, {}, "Fasta textstorlekar hör hemma i Theme.swift")

    def test_theme_has_exactly_three_sizes_and_two_exceptions(self):
        theme = THEME.read_text(encoding="utf-8")
        enum = re.search(r"enum AppTextSize: CGFloat, CaseIterable \{(.*?)\n\}", theme, re.S)
        self.assertIsNotNone(enum)
        self.assertEqual(re.findall(r"case \w+ = (\d+)", enum.group(1)), ["12", "14", "16"])
        # Fasta storlekar i Theme: appens tre (via rawValue), läsytan och mötestimern. Inget annat.
        sizes = re.findall(r"\.system\(size: (size\.rawValue|CGFloat\(ReadingTextSize\.clamped\(size\)\)|\w+)", theme)
        self.assertEqual(sizes, ["size.rawValue", "CGFloat(ReadingTextSize.clamped(size))", "44"])
        self.assertEqual(len(re.findall(r"\.system\(size:", theme)), 3)
        self.assertEqual(re.findall(r"systemFont\(ofSize: (CGFloat\(ReadingTextSize\.clamped\(size\)\)|\w+)", theme),
                         ["CGFloat(ReadingTextSize.clamped(size))"])

    def test_reading_area_defaults_to_the_largest_size(self):
        core = (ROOT / "Packages" / "TranskriberaCore" / "Sources" / "TranskriberaCore" / "ReadingTextSize.swift")
        text = core.read_text(encoding="utf-8")
        self.assertIn("public static let standard: Double = 16", text)
        self.assertIn("public static let steps: [Double] = [14, 16, 18, 20]", text)

    def test_every_window_defaults_to_14_pt(self):
        app = (APP / "App" / "TranskriberaApp.swift").read_text(encoding="utf-8")
        for root in ("ContentView()", "SettingsView()", "TestLabView()"):
            self.assertRegex(app, re.escape(root) + r"\s*\.font\(\.app\(\.regular\)\)", root)

    def test_every_sheet_and_popover_defaults_to_14_pt(self):
        found = {}
        for path in swift_files():
            lines = presentations_without_font(path.read_text(encoding="utf-8"))
            if lines:
                found[str(path.relative_to(ROOT))] = lines
        self.assertEqual(found, {}, "Ark och popovers ska ha .presentationRoot() (se Theme.swift)")

    def test_small_controls_use_an_app_size(self):
        found = {}
        for path in swift_files():
            lines = small_control_violations(path.read_text(encoding="utf-8"))
            if lines:
                found[str(path.relative_to(ROOT))] = lines
        self.assertEqual(found, {}, "Små knappar ger 11 pt; sätt .font(.app(.small))")


class CheckerCatchesViolationsTests(unittest.TestCase):
    """Kontrollen ska faktiskt slå larm på de fel den är till för."""

    def test_catches_text_styles(self):
        self.assertEqual(style_violations('Text("a").font(.caption)\nText("b").font(.callout.weight(.semibold))'), [1, 2])
        self.assertEqual(style_violations('var font: Font = .headline'), [1])
        self.assertEqual(style_violations('.font(.system(.caption, design: .monospaced))'), [1])
        self.assertEqual(style_violations('Text(transcript.title).font(.app(.regular))'), [])

    def test_catches_fixed_sizes(self):
        self.assertEqual(fixed_size_violations('.font(.system(size: 11))\nNSFont.systemFont(ofSize: 10)'), [1, 2])
        self.assertEqual(fixed_size_violations('.font(.app(.small))'), [])

    def test_catches_presentations_without_root(self):
        self.assertEqual(presentations_without_font('.popover(isPresented: $a) {\n    ModelGuideView().font(.app(.regular))\n}'), [1])
        self.assertEqual(presentations_without_font('.popover(isPresented: $a) {\n    ModelGuideView()\n        .presentationRoot()\n}'), [])

    def test_catches_small_buttons_without_size(self):
        self.assertEqual(small_control_violations('Button("Spara") {}\n    .controlSize(.small)'), [2])
        self.assertEqual(small_control_violations('Button("Spara") {}\n    .controlSize(.small)\n    .font(.app(.small))'), [])
        self.assertEqual(small_control_violations('ProgressView().controlSize(.small)'), [])

    def test_catches_sheet_without_size(self):
        self.assertEqual(presentations_without_font('.sheet(isPresented: $x) {\n    Ark()\n}'), [1])
        self.assertEqual(presentations_without_font('.sheet(isPresented: $x) {\n    Ark()\n        .presentationRoot()\n}'), [])


if __name__ == "__main__":
    unittest.main()
