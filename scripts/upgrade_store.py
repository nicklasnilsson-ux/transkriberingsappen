#!/usr/bin/env python3
"""Testdata i appens databas för uppgraderingstestet (scripts/upgrade-test.sh).

  upgrade_store.py seed STORE    Lägger in en känd transkribering i en databas som en
                                 äldre version av appen har skapat.
  upgrade_store.py check STORE   Kontrollerar att transkriberingen finns kvar, oförändrad,
                                 efter att den nya versionen har öppnat databasen.

SwiftData lagrar i Core Datas SQLite-format: en tabell per modell (ZTRANSCRIPT,
ZTRANSCRIPTSEGMENT), kolumner med Z-prefix och nästa primärnyckel i Z_PRIMARYKEY.
"""
from __future__ import annotations

import sqlite3
import sys
import time
import uuid

TITLE = "Uppgraderingstest – får inte försvinna"
TRANSCRIPT_ID = uuid.UUID("6f1c2a3e-6d0b-4f39-9a51-0c2d8e7b4a10")
SEGMENTS = [
    (0, 0.0, 2.5, "Hej och välkommen till intervjun.", "Talare 1"),
    (1, 2.5, 6.0, "Tack, det är roligt att vara här.", "Talare 2"),
]
CORE_DATA_EPOCH = 978307200  # 2001-01-01 i Unix-tid


def columns(db: sqlite3.Connection, table: str) -> set[str]:
    found = {row[1] for row in db.execute(f"PRAGMA table_info({table})")}
    if not found:
        sys.exit(f"Tabellen {table} saknas i databasen.")
    return found


def insert(db: sqlite3.Connection, table: str, entity: str, values: dict) -> int:
    missing = set(values) - columns(db, table)
    if missing:
        sys.exit(f"{table} saknar kolumnerna {sorted(missing)} – har den gamla versionen ett annat schema?")
    ent, last = db.execute("SELECT Z_ENT, Z_MAX FROM Z_PRIMARYKEY WHERE Z_NAME = ?", (entity,)).fetchone()
    pk = last + 1
    row = {"Z_PK": pk, "Z_ENT": ent, "Z_OPT": 1, **values}
    names = ", ".join(row)
    db.execute(f"INSERT INTO {table} ({names}) VALUES ({', '.join('?' * len(row))})", list(row.values()))
    db.execute("UPDATE Z_PRIMARYKEY SET Z_MAX = ? WHERE Z_ENT = ?", (pk, ent))
    return pk


def seed(path: str) -> None:
    db = sqlite3.connect(path)
    with db:
        transcript = insert(db, "ZTRANSCRIPT", "Transcript", {
            "ZID": TRANSCRIPT_ID.bytes,
            "ZTITLE": TITLE,
            "ZCREATEDAT": time.time() - CORE_DATA_EPOCH,
            "ZMEDIAFILENAME": "saknas.m4a",
            "ZORIGINALFILENAME": "intervju.m4a",
            "ZISVIDEO": 0,
            "ZDURATION": 6.0,
            "ZLANGUAGE": "sv",
            "ZMODELNAME": "kb-whisper-small",
            "ZSTATUSRAW": "completed",
            "ZISRECORDING": 0,
        })
        for index, start, end, text, speaker in SEGMENTS:
            insert(db, "ZTRANSCRIPTSEGMENT", "TranscriptSegment", {
                "ZINDEX": index,
                "ZSTART": start,
                "ZEND": end,
                "ZTEXT": text,
                "ZSPEAKER": speaker,
                "ZTRANSCRIPT": transcript,
            })
    print(f"La in transkriberingen \"{TITLE}\" med {len(SEGMENTS)} segment.")


def check(path: str) -> None:
    db = sqlite3.connect(path)
    rows = db.execute("SELECT Z_PK, ZTITLE, ZSTATUSRAW FROM ZTRANSCRIPT WHERE ZID = ?", (TRANSCRIPT_ID.bytes,)).fetchall()
    if len(rows) != 1:
        sys.exit(f"Transkriberingen från den gamla versionen finns inte kvar (hittade {len(rows)}).")
    pk, title, status = rows[0]
    if title != TITLE or status != "completed":
        sys.exit(f"Transkriberingen har ändrats: {title!r}, {status!r}.")
    segments = db.execute(
        "SELECT ZINDEX, ZSTART, ZEND, ZTEXT, ZSPEAKER FROM ZTRANSCRIPTSEGMENT WHERE ZTRANSCRIPT = ? ORDER BY ZINDEX", (pk,)
    ).fetchall()
    if [tuple(s) for s in segments] != SEGMENTS:
        sys.exit(f"Segmenten har ändrats eller försvunnit: {segments}")
    print(f"Transkriberingen och alla {len(SEGMENTS)} segment finns kvar.")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("seed", "check"):
        sys.exit(__doc__)
    {"seed": seed, "check": check}[sys.argv[1]](sys.argv[2])
