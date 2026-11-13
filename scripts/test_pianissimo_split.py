"""Kontroll: delarna av en stor modellfil blir under GitHubs gräns och blir samma fil igen.

Bakgrund 2026-11-13: Pianissimo i 32 bitar blev 2,2 GB och GitHub vägrade ta emot den
(gränsen är 2 GiB per releasefil). Kör: python3 -m unittest discover -s scripts"""
import importlib.util
import os
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("split", ROOT / "scripts/pianissimo/split.py")
split = importlib.util.module_from_spec(spec)
spec.loader.exec_module(split)


class SplitTests(unittest.TestCase):
    def roundtrip(self, size, part_size):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "m.zip"
            data = os.urandom(size)
            path.write_bytes(data)
            parts = split.split(path, part_size, block=7)
            self.assertTrue(all(p.stat().st_size <= part_size for p in parts))
            self.assertEqual([p.name for p in parts], [f"m.zip.part{i}" for i in range(len(parts))])
            joined = b"".join(p.read_bytes() for p in sorted(parts))
            self.assertEqual(joined, data)
            return len(parts)

    def test_parts_are_small_enough_and_join_to_the_same_file(self):
        self.assertEqual(self.roundtrip(100, 30), 4)
        self.assertEqual(self.roundtrip(90, 30), 3)
        self.assertEqual(self.roundtrip(10, 30), 1)

    def test_limit_is_under_two_gib(self):
        self.assertLess(split.LIMIT, 2 * 1024**3)


if __name__ == "__main__":
    unittest.main()
