#!/usr/bin/env python3
"""CHANGELOG.md för releaser.

  changelog.py check VERSION   Avbryter om CHANGELOG.md saknar ett avsnitt "## [VERSION]".
  changelog.py notes VERSION   Skriver ut avsnittet för VERSION (Markdown), eller inget.
  changelog.py released        Avbryter om avsnittet för en redan släppt version (git-taggen
                               vVERSION finns) har ändrats sedan releasen. Det händer lätt när
                               en PR med punkter under [Kommande] slås ihop efter en
                               versionshöjning: git lägger då punkterna i den släppta versionen.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

CHANGELOG = Path(__file__).resolve().parent.parent / "CHANGELOG.md"


def section(text: str, version: str) -> str | None:
    heading = re.compile(rf"^## \[{re.escape(version)}\][^\n]*$", re.M)
    match = heading.search(text)
    if not match:
        return None
    rest = text[match.end():]
    following = re.search(r"^## ", rest, re.M)
    body = rest[: following.start()] if following else rest
    return body.strip()


def versions(text: str) -> list[str]:
    return [v for v in re.findall(r"^## \[([^\]]+)\]", text, re.M) if v != "Kommande"]


def changed_released(text: str, released_text) -> list[str]:
    """Versioner vars avsnitt skiljer sig från CHANGELOG.md vid releasen.

    `released_text(version)` ger CHANGELOG.md som den såg ut vid releasen, eller None om
    versionen inte är släppt (eller saknade avsnitt då)."""
    changed = []
    for version in versions(text):
        old = released_text(version)
        old_body = section(old, version) if old is not None else None
        if old_body is not None and old_body != section(text, version):
            changed.append(version)
    return changed


def text_at_tag(version: str) -> str | None:
    result = subprocess.run(
        ["git", "show", f"v{version}:CHANGELOG.md"],
        cwd=CHANGELOG.parent, capture_output=True, text=True, encoding="utf-8",
    )
    return result.stdout if result.returncode == 0 else None


def main(argv: list[str]) -> None:
    if len(argv) == 2 and argv[1] == "released":
        path = Path(os.environ.get("CHANGELOG", CHANGELOG))
        changed = changed_released(path.read_text(encoding="utf-8"), text_at_tag)
        if changed:
            sys.exit(
                "CHANGELOG.md: avsnittet för redan släppta " + ", ".join(changed) + " har ändrats. "
                "Nya punkter ska stå under \"## [Kommande]\" (jämför med git show v<VERSION>:CHANGELOG.md)."
            )
        print("CHANGELOG.md: släppta versioners avsnitt är oförändrade.")
        return
    if len(argv) != 3 or argv[1] not in ("check", "notes"):
        sys.exit(__doc__)
    command, version = argv[1], argv[2]
    path = Path(os.environ.get("CHANGELOG", CHANGELOG))
    body = section(path.read_text(encoding="utf-8"), version)
    if command == "check":
        if not body:
            sys.exit(
                f"CHANGELOG.md saknar ett avsnitt för {version}. Byt rubriken \"## [Kommande]\" till "
                f"\"## [{version}] – ÅÅÅÅ-MM-DD\" (eller lägg till ett nytt avsnitt) i samma PR som höjer versionen."
            )
        print(f"CHANGELOG.md har ett avsnitt för {version}.")
    elif body:
        print(body)


if __name__ == "__main__":
    main(sys.argv)
