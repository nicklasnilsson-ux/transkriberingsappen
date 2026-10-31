#!/usr/bin/env python3
"""Sparkle-appcast för Transkribera.

  appcast.py check APPCAST --version BUILD
      Avbryter om BUILD inte är högre än alla versioner som redan finns i appcasten.

  appcast.py add APPCAST --archive ZIP --url URL --version BUILD --short-version VERSION
                 [--channel beta] [--notes FILE] [--notes-link URL]
      Signerar ZIP med EdDSA (nyckeln i miljövariabeln SPARKLE_PRIVATE_KEY, base64) och
      lägger in den som ny version överst i appcasten. Signaturen kontrolleras mot
      SUPublicEDKey i project.yml (eller --public-key) innan något skrivs.

  appcast.py verify APPCAST --archive ZIP --url URL --version BUILD --short-version VERSION
      Körs efter publiceringen på filen så som den ligger publicerad: appcasten ska ha en
      post med rätt version, adress, storlek och signatur. Annars avbryts bygget.

Kräver paketet `cryptography` för `add` och `verify`.
"""
from __future__ import annotations

import argparse
import base64
import html
import os
import re
import sys
import xml.etree.ElementTree as ET
from email.utils import formatdate
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)

MINIMUM_SYSTEM_VERSION = "14.0"
MAX_ITEMS = 30


def sp(tag: str) -> str:
    return f"{{{SPARKLE_NS}}}{tag}"


def version_key(version: str) -> tuple[int, ...]:
    """Jämför byggnummer som Sparkle gör för rena sifferversioner: 3 < 3.17 < 4."""
    return tuple(int(part) for part in re.findall(r"\d+", version))


def load(path: Path) -> ET.ElementTree:
    if path.exists():
        return ET.parse(path)
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Transkribera"
    ET.SubElement(channel, "link").text = "https://github.com/nicklasnilsson-ux/transkriberingsappen"
    ET.SubElement(channel, "description").text = "Uppdateringar för Transkribera"
    ET.SubElement(channel, "language").text = "sv"
    return ET.ElementTree(rss)


def items(tree: ET.ElementTree) -> list[ET.Element]:
    return tree.getroot().find("channel").findall("item")


def check(tree: ET.ElementTree, version: str) -> None:
    for item in items(tree):
        existing = item.findtext(sp("version"), "")
        if existing != version and version_key(existing) >= version_key(version):
            sys.exit(
                f"Byggnumret {version} måste vara högre än {existing} som redan finns i appcasten. "
                "Höj CURRENT_PROJECT_VERSION i project.yml."
            )


def sign(archive: bytes, private_key_b64: str, public_key_b64: str) -> str:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
    from cryptography.hazmat.primitives import serialization

    secret = base64.b64decode(private_key_b64.strip())
    # generate_keys från Sparkle exporterar antingen fröet (32 byte) eller ett äldre 96-bytesformat.
    if len(secret) == 96:
        secret = secret[:32]
    if len(secret) != 32:
        sys.exit("SPARKLE_PRIVATE_KEY har fel format (förväntade base64 av en 32-bytes Ed25519-nyckel).")
    key = Ed25519PrivateKey.from_private_bytes(secret)
    signature = key.sign(archive)

    expected = base64.b64decode(public_key_b64)
    actual = key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    if actual != expected:
        sys.exit("SPARKLE_PRIVATE_KEY hör inte ihop med SUPublicEDKey i project.yml.")
    Ed25519PublicKey.from_public_bytes(expected).verify(signature, archive)
    return base64.b64encode(signature).decode()


def verify(tree: ET.ElementTree, *, archive: bytes, url: str, version: str, short_version: str, public_key_b64: str) -> None:
    """Kontrollerar att appcasten pekar på just den publicerade filen: version, adress, storlek och signatur."""
    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

    found = [i for i in items(tree) if i.findtext(sp("version"), "") == version]
    if len(found) != 1:
        sys.exit(f"Appcasten har {len(found)} poster med byggnummer {version}, förväntade 1.")
    item = found[0]
    if item.findtext(sp("shortVersionString"), "") != short_version:
        sys.exit(f"Appcasten anger version {item.findtext(sp('shortVersionString'), '')}, förväntade {short_version}.")
    enclosure = item.find("enclosure")
    if enclosure is None or enclosure.get("url") != url:
        sys.exit(f"Appcasten pekar på {enclosure.get('url') if enclosure is not None else 'ingen fil'}, förväntade {url}.")
    if enclosure.get("length") != str(len(archive)):
        sys.exit(f"Appcasten anger storleken {enclosure.get('length')}, filen är {len(archive)} byte.")
    try:
        signature = base64.b64decode(enclosure.get(sp("edSignature"), ""))
        Ed25519PublicKey.from_public_bytes(base64.b64decode(public_key_b64)).verify(signature, archive)
    except (InvalidSignature, ValueError):
        sys.exit("Signaturen i appcasten stämmer inte med den publicerade filen.")


def markdown_to_html(text: str) -> str:
    """Enkel omvandling av GitHubs genererade release notes till HTML för Sparkles dialog."""

    def inline(line: str) -> str:
        line = html.escape(line)
        line = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", line)
        line = re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", r'<a href="\2">\1</a>', line)
        line = re.sub(r"(?<![\"'>])(https?://[^\s<]+)", r'<a href="\1">\1</a>', line)
        return line

    out: list[str] = []
    in_list = False
    for raw in text.splitlines():
        line = raw.strip()
        bullet = re.match(r"^[*-]\s+(.*)", line)
        if bullet:
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{inline(bullet.group(1))}</li>")
            continue
        # Indragen rad direkt efter en punkt hör till samma punkt (radbrytning i CHANGELOG.md).
        if in_list and line and raw[:1].isspace():
            out[-1] = out[-1][: -len("</li>")] + f" {inline(line)}</li>"
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
        if not line or line.startswith("<!--"):
            continue
        heading = re.match(r"^#+\s+(.*)", line)
        out.append(f"<h3>{inline(heading.group(1))}</h3>" if heading else f"<p>{inline(line)}</p>")
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


def add(
    tree: ET.ElementTree,
    *,
    archive: Path,
    url: str,
    version: str,
    short_version: str,
    signature: str,
    channel: str | None,
    notes_html: str,
    notes_link: str | None,
    pub_date: str | None = None,
) -> None:
    check(tree, version)
    root_channel = tree.getroot().find("channel")
    for item in items(tree):
        if item.findtext(sp("version")) == version:
            root_channel.remove(item)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {short_version}"
    ET.SubElement(item, "pubDate").text = pub_date or formatdate(usegmt=True)
    ET.SubElement(item, sp("version")).text = version
    ET.SubElement(item, sp("shortVersionString")).text = short_version
    ET.SubElement(item, sp("minimumSystemVersion")).text = MINIMUM_SYSTEM_VERSION
    if channel:
        ET.SubElement(item, sp("channel")).text = channel
    if notes_link:
        ET.SubElement(item, sp("fullReleaseNotesLink")).text = notes_link
    if notes_html:
        ET.SubElement(item, "description").text = notes_html
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": url,
            "length": str(archive.stat().st_size),
            "type": "application/octet-stream",
            sp("edSignature"): signature,
        },
    )

    # Nyaste versionen först; äldre poster rensas bort efter hand.
    existing = items(tree)
    for old in existing:
        root_channel.remove(old)
    ordered = sorted(existing + [item], key=lambda e: version_key(e.findtext(sp("version"), "")), reverse=True)
    for entry in ordered[:MAX_ITEMS]:
        root_channel.append(entry)


def write(tree: ET.ElementTree, path: Path) -> None:
    ET.indent(tree, space="  ")
    path.parent.mkdir(parents=True, exist_ok=True)
    tree.write(path, encoding="utf-8", xml_declaration=True)
    with path.open("a", encoding="utf-8") as f:
        f.write("\n")


def public_key_from_project(project: Path) -> str:
    match = re.search(r"^\s*SUPublicEDKey:\s*\"?([A-Za-z0-9+/=]+)\"?\s*$", project.read_text(), re.M)
    if not match:
        sys.exit(f"Hittade ingen SUPublicEDKey i {project}.")
    return match.group(1)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p_check = sub.add_parser("check")
    p_check.add_argument("appcast", type=Path)
    p_check.add_argument("--version", required=True)

    p_verify = sub.add_parser("verify")
    p_verify.add_argument("appcast", type=Path)
    p_verify.add_argument("--archive", type=Path, required=True, help="Filen så som den ligger publicerad")
    p_verify.add_argument("--url", required=True)
    p_verify.add_argument("--version", required=True)
    p_verify.add_argument("--short-version", required=True)
    p_verify.add_argument("--public-key")
    p_verify.add_argument("--project", type=Path, default=Path(__file__).resolve().parent.parent / "project.yml")

    p_add = sub.add_parser("add")
    p_add.add_argument("appcast", type=Path)
    p_add.add_argument("--archive", type=Path, required=True)
    p_add.add_argument("--url", required=True)
    p_add.add_argument("--version", required=True)
    p_add.add_argument("--short-version", required=True)
    p_add.add_argument("--channel")
    p_add.add_argument("--notes", type=Path, help="Release notes i Markdown")
    p_add.add_argument("--notes-link")
    p_add.add_argument("--public-key")
    p_add.add_argument("--project", type=Path, default=Path(__file__).resolve().parent.parent / "project.yml")

    args = parser.parse_args()
    tree = load(args.appcast)

    if args.command == "check":
        check(tree, args.version)
        print(f"Byggnummer {args.version} är OK.")
        return

    if args.command == "verify":
        verify(
            tree,
            archive=args.archive.read_bytes(),
            url=args.url,
            version=args.version,
            short_version=args.short_version,
            public_key_b64=args.public_key or public_key_from_project(args.project),
        )
        print(f"Appcasten pekar rätt för {args.short_version} ({args.version}).")
        return

    private_key = os.environ.get("SPARKLE_PRIVATE_KEY", "")
    if not private_key:
        sys.exit("SPARKLE_PRIVATE_KEY saknas.")
    public_key = args.public_key or public_key_from_project(args.project)
    signature = sign(args.archive.read_bytes(), private_key, public_key)
    notes = args.notes.read_text() if args.notes and args.notes.exists() else ""
    add(
        tree,
        archive=args.archive,
        url=args.url,
        version=args.version,
        short_version=args.short_version,
        signature=signature,
        channel=args.channel or None,
        notes_html=markdown_to_html(notes),
        notes_link=args.notes_link,
    )
    write(tree, args.appcast)
    print(f"La till {args.short_version} ({args.version}) i {args.appcast}.")


if __name__ == "__main__":
    main()
