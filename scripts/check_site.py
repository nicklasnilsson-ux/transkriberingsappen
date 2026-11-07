#!/usr/bin/env python3
"""Kontrollerar landningssidan i site/ innan den publiceras på GitHub Pages.

Fångar det som annars syns först när sidan är ute:
- en lokal länk eller bild som saknas,
- en nedladdningsknapp som inte fungerar utan JavaScript (ingen reservlänk),
- skript, typsnitt eller stilmallar från andra tjänster (sidan lovar att inte ha det),
- länkar till fel repo, t.ex. efter ett namnbyte (jämförs med SUFeedURL i project.yml),
- bilder utan alt-text, saknat lang="sv",
- andra filtyper än de som hör till en statisk sida (så att inget annat råkar publiceras),
- ikon och favicon som inte är exakt appens ikon (byts appikonen ska sidan följa med),
- texter som Nicklas har bestämt ska stå kvar (förbehållet, sidfoten) och klarspråk:
  förkortningar som t.ex. skrivs ut, inga onödigt långa meningar.

Kör: python3 scripts/check_site.py
"""
from __future__ import annotations

import re
import sys
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
ALLOWED_SUFFIXES = {".html", ".png", ".svg", ".ico", ".jpg", ".jpeg", ".webp", ""}
ALLOWED_FILES_WITHOUT_SUFFIX = {".nojekyll"}
# Den enda externa adress som skriptet får fråga (senaste release).
ALLOWED_FETCH = "https://api.github.com/repos/"


ICONSET = ROOT / "Transkribera" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
SITE_ICONS = {"icon-512.png": "icon_256x256@2x.png", "favicon.png": "icon_32x32@2x.png"}


def check_icons() -> list[str]:
    errors: list[str] = []
    for site_name, app_name in SITE_ICONS.items():
        site_file, app_file = SITE / site_name, ICONSET / app_name
        if not site_file.exists():
            errors.append(f"site/{site_name} saknas")
        elif not app_file.exists():
            errors.append(f"appens ikon {app_file.relative_to(ROOT)} saknas")
        elif site_file.read_bytes() != app_file.read_bytes():
            errors.append(f"site/{site_name} är inte appens nuvarande ikon (kopiera {app_name} från {ICONSET.relative_to(ROOT)})")
    return errors


def repo_slug() -> str:
    text = (ROOT / "project.yml").read_text(encoding="utf-8")
    m = re.search(r"SUFeedURL:\s*https://raw\.githubusercontent\.com/([^/]+/[^/]+)/", text)
    if not m:
        raise SystemExit("Hittar inte SUFeedURL i project.yml")
    return m.group(1)


class Collector(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.tags: list[tuple[str, dict[str, str | None]]] = []
        self.scripts: list[str] = []
        self.text: list[str] = []
        self._in_script = False
        self._in_style = False

    def handle_starttag(self, tag, attrs):
        self.tags.append((tag, dict(attrs)))
        if tag == "script":
            self._in_script = True
            self.scripts.append("")
        if tag == "style":
            self._in_style = True
        if tag in BLOCK_TAGS:
            self.text.append("\n")

    def handle_startendtag(self, tag, attrs):
        self.tags.append((tag, dict(attrs)))

    def handle_endtag(self, tag):
        if tag == "script":
            self._in_script = False
        if tag == "style":
            self._in_style = False
        if tag in BLOCK_TAGS:
            self.text.append("\n")

    def handle_data(self, data):
        if self._in_script:
            self.scripts[-1] += data
        elif not self._in_style:
            self.text.append(data)


# Texter som ska finnas kvar på sidan (beslut av Nicklas 2026-11-03).
REQUIRED_TEXT = [
    "Tidig version.",
    "Anonymiseringen hjälper men bör granskas.",
    "Gjord av Nicklas Nilsson",
]
REQUIRED_LINK = "https://www.linkedin.com/in/nicklas-nilsson-b3408296/"
# Klarspråk: skriv ut förkortningar och använd Språkrådets stavning.
AVOID = {
    r"\bt\.\s?ex\.": "skriv ut ”till exempel”",
    r"\bbl\.\s?a\.": "skriv ut ”bland annat”",
    r"\bm\.\s?m\.": "skriv ut ”med mera” eller ”och liknande”",
    r"\bosv\.": "skriv ut ”och så vidare”",
    r"\bs\.\s?k\.": "skriv ut ”så kallad”",
    r"\bscroll": "skriv ”skrolla”",
}
MAX_WORDS_PER_SENTENCE = 30
BLOCK_TAGS = {"p", "li", "dt", "dd", "h1", "h2", "h3", "summary", "title", "div", "section"}


def check_language(name, c: Collector, html: str) -> list[str]:
    errors: list[str] = []
    text = re.sub(r"[ \t]+", " ", "".join(c.text))
    flat = " ".join(text.split())
    for phrase in REQUIRED_TEXT:
        if phrase not in flat:
            errors.append(f"{name}: texten ”{phrase}” ska finnas kvar")
    if REQUIRED_LINK not in html:
        errors.append(f"{name}: länken till LinkedIn i sidfoten ska finnas kvar")
    metas = [a.get("content") or "" for t, a in c.tags if t == "meta" and a.get("content")
             and (a.get("name") == "description" or (a.get("property") or "").endswith(("title", "description")))]
    for block in text.split("\n") + metas:
        for pattern, hint in AVOID.items():
            for m in re.finditer(pattern, block, re.IGNORECASE):
                errors.append(f"{name}: ”{m.group(0)}” – {hint}")
        for sentence in re.split(r"(?<=[.!?:])\s+", block.strip()):
            words = len(sentence.split())
            if words > MAX_WORDS_PER_SENTENCE:
                errors.append(f"{name}: meningen har {words} ord (högst {MAX_WORDS_PER_SENTENCE}), dela upp den: ”{sentence[:70]}…”")
    return errors


def check_page(page: Path, slug: str) -> list[str]:
    errors: list[str] = []
    name = page.relative_to(ROOT)
    html = page.read_text(encoding="utf-8")
    c = Collector()
    c.feed(html)

    html_tags = [a for t, a in c.tags if t == "html"]
    if not html_tags or html_tags[0].get("lang") != "sv":
        errors.append(f"{name}: <html> ska ha lang=\"sv\"")

    errors.extend(check_language(name, c, html))

    ids = {a["id"] for _, a in c.tags if a.get("id")}

    for tag, attrs in c.tags:
        if tag == "img" and attrs.get("alt") is None:
            errors.append(f"{name}: <img src={attrs.get('src')!r}> saknar alt (använd alt=\"\" för dekor)")
        if tag == "script" and attrs.get("src"):
            errors.append(f"{name}: externt eller separat skript ({attrs['src']}) är inte tillåtet")
        if tag == "link" and attrs.get("rel") in ("stylesheet", "preconnect", "preload") :
            errors.append(f"{name}: <link rel={attrs['rel']}> mot {attrs.get('href')} är inte tillåtet")
        for key in ("href", "src"):
            url = attrs.get(key)
            if url is None:
                continue
            if url.startswith("#"):
                if url != "#" and url[1:] not in ids:
                    errors.append(f"{name}: ankaret {url} finns inte på sidan")
            elif url.startswith(("http://",)):
                errors.append(f"{name}: {url} ska vara https")
            elif url.startswith("https://"):
                m = re.match(r"https://github\.com/([^/]+/[^/#?]+)", url)
                if m and m.group(1).lower().startswith(slug.split("/")[0].lower() + "/") and m.group(1) != slug:
                    errors.append(f"{name}: {url} pekar på {m.group(1)}, men appen använder {slug}")
                if tag in ("img", "script", "link") and key == "src":
                    errors.append(f"{name}: {url} hämtas från en annan tjänst")
            elif url.startswith(("mailto:",)):
                pass
            elif "://" not in url:
                target = (page.parent / url.split("#")[0].split("?")[0])
                if url.split("#")[0] and not (target.exists() or (target / "index.html").exists()):
                    errors.append(f"{name}: lokal länk {url} finns inte")

    button = [a for t, a in c.tags if t == "a" and a.get("id") == "ladda-ner"]
    if not button:
        errors.append(f"{name}: nedladdningsknappen (id=ladda-ner) saknas")
    elif button[0].get("href") != f"https://github.com/{slug}/releases/latest":
        errors.append(f"{name}: nedladdningsknappen ska utan JavaScript gå till https://github.com/{slug}/releases/latest")

    for script in c.scripts:
        for url in re.findall(r"https?://[^\s\"'`)]+", script):
            if url.startswith("https://github.com/"):
                continue  # bara mönster för att kontrollera nedladdningslänken
            if not url.startswith(ALLOWED_FETCH):
                errors.append(f"{name}: skriptet anropar {url}")
        m = re.search(r'var repo = "([^"]+)"', script)
        if m and m.group(1) != slug:
            errors.append(f"{name}: skriptet använder repot {m.group(1)}, men appen använder {slug}")
    return errors


def main() -> int:
    if not SITE.is_dir():
        print("site/ saknas")
        return 1
    slug = repo_slug()
    errors: list[str] = []
    pages = sorted(SITE.rglob("*.html"))
    if SITE / "index.html" not in pages:
        errors.append("site/index.html saknas")
    for path in sorted(SITE.rglob("*")):
        if path.is_file() and path.suffix.lower() not in ALLOWED_SUFFIXES:
            errors.append(f"{path.relative_to(ROOT)}: filtypen hör inte hemma på landningssidan")
        if path.is_file() and path.suffix == "" and path.name not in ALLOWED_FILES_WITHOUT_SUFFIX:
            errors.append(f"{path.relative_to(ROOT)}: okänd fil")
    errors.extend(check_icons())
    for page in pages:
        errors.extend(check_page(page, slug))
    for e in errors:
        print("FEL:", e)
    if errors:
        return 1
    print(f"Landningssidan OK ({len(pages)} sida/sidor, repo {slug})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
