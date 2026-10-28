#!/usr/bin/env python3
"""CHANGELOG.md för releaser.

  changelog.py check VERSION   Avbryter om CHANGELOG.md saknar ett avsnitt "## [VERSION]".
  changelog.py notes VERSION   Skriver ut avsnittet för VERSION (Markdown), eller inget.
"""
from __future__ import annotations

import os
import re
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


def main(argv: list[str]) -> None:
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
