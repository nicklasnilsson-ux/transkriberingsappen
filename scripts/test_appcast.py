"""Tester för scripts/appcast.py. Kör: python3 -m unittest discover -s scripts"""
import base64
import os
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey

SCRIPT = Path(__file__).resolve().parent / "appcast.py"
NS = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}


class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        key = Ed25519PrivateKey.generate()
        self.private = base64.b64encode(
            key.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption())
        ).decode()
        self.public = base64.b64encode(
            key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        ).decode()
        self.appcast = self.dir / "appcast.xml"

    def run_script(self, *args, key=None, check=True):
        env = dict(os.environ, SPARKLE_PRIVATE_KEY=key if key is not None else self.private)
        return subprocess.run([sys.executable, str(SCRIPT), *args], env=env, capture_output=True, text=True, check=check)

    def add(self, version, short, channel=None, notes=None, **kw):
        archive = self.dir / f"Transkribera-{short}.zip"
        archive.write_bytes(os.urandom(1000))
        args = ["add", str(self.appcast), "--archive", str(archive), "--url", f"https://example.com/{short}.zip",
                "--version", version, "--short-version", short, "--public-key", self.public]
        if channel:
            args += ["--channel", channel]
        if notes:
            path = self.dir / "notes.md"
            path.write_text(notes)
            args += ["--notes", str(path)]
        return archive, self.run_script(*args, **kw)

    def items(self):
        return ET.parse(self.appcast).getroot().find("channel").findall("item")

    def test_signature_verifies(self):
        archive, _ = self.add("4", "0.4.0")
        (item,) = self.items()
        enclosure = item.find("enclosure")
        signature = base64.b64decode(enclosure.get(f"{{{NS['sparkle']}}}edSignature"))
        Ed25519PublicKey.from_public_bytes(base64.b64decode(self.public)).verify(signature, archive.read_bytes())
        self.assertEqual(enclosure.get("length"), "1000")
        self.assertEqual(item.findtext("sparkle:minimumSystemVersion", namespaces=NS), "14.0")
        self.assertIsNone(item.find("sparkle:channel", NS))

    def test_beta_channel_and_order(self):
        self.add("4", "0.4.0")
        self.add("4.17", "0.5.0-beta.17", channel="beta")
        self.add("5", "0.5.0")
        versions = [i.findtext("sparkle:version", namespaces=NS) for i in self.items()]
        self.assertEqual(versions, ["5", "4.17", "4"])
        beta = self.items()[1]
        self.assertEqual(beta.findtext("sparkle:channel", namespaces=NS), "beta")

    def test_rejects_lower_or_equal_build(self):
        self.add("4", "0.4.0")
        _, result = self.add("3.9", "0.4.0-beta.9", channel="beta", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("måste vara högre", result.stderr)
        result = self.run_script("check", str(self.appcast), "--version", "4.1")
        self.assertEqual(result.returncode, 0)

    def test_same_build_replaces_item(self):
        self.add("4", "0.4.0")
        self.add("4", "0.4.0")
        self.assertEqual(len(self.items()), 1)

    def test_wrong_key_is_rejected(self):
        other = base64.b64encode(os.urandom(32)).decode()
        _, result = self.add("4", "0.4.0", key=other, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.appcast.exists())

    def verify(self, archive, **overrides):
        args = {"--url": "https://example.com/0.4.0.zip", "--version": "4", "--short-version": "0.4.0"}
        args.update(overrides)
        flat = [x for pair in args.items() for x in pair]
        return self.run_script("verify", str(self.appcast), "--archive", str(archive), "--public-key", self.public,
                               *flat, check=False)

    def test_verify_accepts_the_published_file(self):
        archive, _ = self.add("4", "0.4.0")
        self.assertEqual(self.verify(archive).returncode, 0)

    def test_verify_rejects_a_changed_file(self):
        archive, _ = self.add("4", "0.4.0")
        other = self.dir / "other.zip"
        other.write_bytes(archive.read_bytes()[:-1] + b"x")
        self.assertNotEqual(self.verify(other).returncode, 0)

    def test_verify_rejects_missing_wrong_version_and_wrong_url(self):
        archive, _ = self.add("4", "0.4.0")
        self.assertNotEqual(self.verify(archive, **{"--version": "5"}).returncode, 0)
        self.assertNotEqual(self.verify(archive, **{"--short-version": "0.4.1"}).returncode, 0)
        self.assertNotEqual(self.verify(archive, **{"--url": "https://example.com/x.zip"}).returncode, 0)

    def test_release_notes_become_html(self):
        self.add("4", "0.4.0", notes="## What's Changed\n* Lägg till <uppdateringar> by @x in https://github.com/a/b/pull/10\n")
        description = self.items()[0].findtext("description")
        self.assertIn("<h3>What&#x27;s Changed</h3>", description)
        self.assertIn("<li>Lägg till &lt;uppdateringar&gt;", description)
        self.assertIn('<a href="https://github.com/a/b/pull/10">', description)


if __name__ == "__main__":
    unittest.main()
