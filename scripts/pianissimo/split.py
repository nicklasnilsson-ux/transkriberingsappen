"""Delar en fil i delar under GitHubs gräns på 2 GiB per releasefil.

Delarna heter <fil>.part0, <fil>.part1 … och sätts ihop med cat i namnordning, eller av
appen (ModelDownloader). Kör: python3 scripts/pianissimo/split.py FIL [--size BYTE]"""
import argparse
from pathlib import Path

LIMIT = 2_000_000_000  # under 2 GiB (2 147 483 648) med marginal


def split(path: Path, size: int = LIMIT, block: int = 64 * 1024 * 1024) -> list[Path]:
    """Strömmar filen i block, så att hela delen aldrig ligger i minnet."""
    total = path.stat().st_size
    count = max(1, -(-total // size))
    if count > 10:
        raise SystemExit("Fler än 10 delar: namnordningen part10 < part2 skulle bli fel.")
    parts = []
    with path.open("rb") as source:
        for index in range(count):
            part = path.with_name(f"{path.name}.part{index}")
            left = min(size, total - index * size)
            with part.open("wb") as out:
                while left > 0:
                    chunk = source.read(min(block, left))
                    if not chunk:
                        raise SystemExit(f"{path} tog slut för tidigt")
                    out.write(chunk)
                    left -= len(chunk)
            parts.append(part)
    return parts


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("file", type=Path)
    parser.add_argument("--size", type=int, default=LIMIT)
    args = parser.parse_args()
    for part in split(args.file, args.size):
        print(part)
