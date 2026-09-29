"""Complete official Bulário catalogue ingestion; metadata is never clinical text.

The headerless positional layouts below were observed in the official exports
dated 2026-09-25. Unconfirmed columns stay positional, not invented semantics.
"""
from __future__ import annotations

import argparse
import asyncio
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import re
import sqlite3
import sys
from datetime import datetime, timezone
import uuid

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

BASE = "https://dados.anvisa.gov.br/dados/CONSULTAS/DOCUMENTOS/"
FILES = {"product": "TA_CONSULTA_BULA_PRODUTO.CSV",
         "document": "TA_CONSULTA_BULA_DOCUMENTO.CSV"}
WIDTHS = {"product": 12, "document": 10}
VERSION = "anvisa-bulario-catalogue/1"


def digest(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def parse(content: bytes, kind: str) -> list[dict]:
    if not content or content.lstrip().startswith(b"<"):
        raise ValueError("Empty export or HTML response; catalogue not replaced")
    try:
        text = content.decode("utf-8-sig")
    except UnicodeDecodeError:
        text = content.decode("latin-1")
    records = []
    for ordinal, row in enumerate(csv.reader(io.StringIO(text), delimiter=";", strict=True), 1):
        if len(row) != WIDTHS[kind]:
            raise ValueError(f"{kind} record {ordinal}: expected {WIDTHS[kind]} columns, got {len(row)}")
        process = row[4] if kind == "product" else row[0]
        if not re.fullmatch(r"\d{5,25}", process):
            raise ValueError(f"{kind} record {ordinal}: unexpected process format")
        # Keep IDs as strings, including leading zeros. Never join by drug name.
        record = {"record_number": ordinal, "process_number": process,
                  "raw_columns": row, "content_status": "metadata_only"}
        if kind == "product":
            if (row[2] and not re.fullmatch(r"\d{9}", row[2])) or not row[0].isdigit():
                raise ValueError(f"product record {ordinal}: unexpected registration/ID")
            record.update(product_id=row[0], product_name=row[1],
                          registration_number=row[2], company_cnpj=row[5],
                          company_name=row[6], document_id=row[7])
        else:
            if not row[1].isdigit():
                raise ValueError(f"document record {ordinal}: unexpected ID")
            record.update(document_id=row[1], document_status=row[4])
        record["row_sha256"] = digest(json.dumps(row, ensure_ascii=False).encode())
        records.append(record)
    if not records:
        raise ValueError("No records; catalogue not replaced")
    return records


async def download(kind: str) -> bytes:
    import httpx
    url = BASE + FILES[kind]
    async with httpx.AsyncClient(timeout=180, follow_redirects=True,
                                headers={"User-Agent": "Nursing-Bulario-ETL/1.0"}) as client:
        for attempt in range(4):
            try:
                response = await client.get(url)
                if response.status_code in (401, 403):
                    raise RuntimeError(f"Access denied for {FILES[kind]}; no bypass attempted")
                if response.status_code == 429 or response.status_code >= 500:
                    if attempt < 3:
                        delay = response.headers.get("Retry-After", "")
                        if delay.isdigit() and int(delay) > 60:
                            raise RuntimeError("Retry-After exceeds run budget; retry later")
                        await asyncio.sleep(int(delay) if delay.isdigit() else 2 ** (attempt + 1))
                        continue
                response.raise_for_status()
                return response.content
            except httpx.TransportError:
                if attempt == 3:
                    raise
                await asyncio.sleep(2 ** (attempt + 1))
    raise RuntimeError("Download retries exhausted")


def write_catalogue(target: Path, datasets: dict, hashes: dict) -> dict:
    """Publish a complete SQLite generation atomically; retain all source rows."""
    temp = target.with_suffix(f".{uuid.uuid4().hex}.tmp")
    conn = sqlite3.connect(temp)
    try:
        conn.executescript("""
            CREATE TABLE catalogue(kind TEXT, row_number INTEGER, process_number TEXT,
              registration_number TEXT, document_id TEXT, payload TEXT,
              PRIMARY KEY(kind,row_number));
            CREATE INDEX catalogue_process ON catalogue(process_number);
            CREATE INDEX catalogue_registration ON catalogue(registration_number);
            CREATE INDEX catalogue_document ON catalogue(document_id);
            CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT);
        """)
        for kind, records in datasets.items():
            conn.executemany("INSERT INTO catalogue VALUES(?,?,?,?,?,?)", [
                (kind, r["record_number"], r["process_number"],
                 r.get("registration_number"), r["document_id"],
                 json.dumps(r, ensure_ascii=False)) for r in records])
        matched = conn.execute("""SELECT count(*) FROM catalogue p WHERE p.kind='product'
            AND EXISTS(SELECT 1 FROM catalogue d WHERE d.kind='document'
              AND d.process_number=p.process_number AND d.document_id=p.document_id)""").fetchone()[0]
        summary = {"version": VERSION, "collected_at": datetime.now(timezone.utc).isoformat(),
                   "source_sha256": hashes, "products": len(datasets["product"]),
                   "document_records": len(datasets["document"]),
                   "products_with_exact_document_match": matched,
                   "products_without_exact_document_match": len(datasets["product"]) - matched,
                   "products_without_registration": sum(not r["registration_number"] for r in datasets["product"]),
                   "pdfs_downloaded": 0, "full_texts_available": 0,
                   "status": "catalogue_complete_full_text_pending",
                   "pending_reason": "Official CSVs contain metadata, not PDF URLs or leaflet text"}
        conn.execute("INSERT INTO metadata VALUES('summary',?)", (json.dumps(summary),))
        conn.commit()
    finally:
        conn.close()
    os.replace(temp, target)
    return summary


async def import_postgres(database_url: str, datasets: dict, raw_paths: dict, hashes: dict) -> dict:
    from sqlalchemy import insert, select, text
    from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
    from app.db.models import SourceAssertion, SourceSnapshot, SourceSystem
    engine = create_async_engine(database_url)
    inserted = {}
    try:
        async with async_sessionmaker(engine)() as session, session.begin():
            # Serialize this importer; the source/checksum unique key also guards idempotency.
            await session.execute(text("SELECT pg_advisory_xact_lock(768231045)"))
            source = await session.scalar(select(SourceSystem).where(SourceSystem.code == "ANVISA_BULARIO"))
            if source is None:
                source = SourceSystem(code="ANVISA_BULARIO", name="ANVISA Bulário — dados abertos",
                                      country_code="BR", base_url=BASE, authority_level=100)
                session.add(source)
                await session.flush()
            for kind, records in datasets.items():
                existing = await session.scalar(select(SourceSnapshot).where(
                    SourceSnapshot.source_system_id == source.id,
                    SourceSnapshot.checksum_sha256 == hashes[kind]))
                if existing is not None:
                    inserted[kind] = 0
                    continue
                snapshot = SourceSnapshot(source_system_id=source.id, dataset_name=FILES[kind],
                    checksum_sha256=hashes[kind], raw_object_uri=raw_paths[kind].resolve().as_uri(),
                    etl_version=VERSION, schema_version=f"headerless-{WIDTHS[kind]}-columns-v1",
                    snapshot_metadata={"row_count": len(records), "source_url": BASE + FILES[kind],
                                       "content_status": "metadata_only"})
                session.add(snapshot)
                await session.flush()
                for start in range(0, len(records), 500):
                    await session.execute(insert(SourceAssertion), [{
                        "source_snapshot_id": snapshot.id,
                        "external_record_id": r.get("product_id", r["document_id"]),
                        "entity_type": f"anvisa_bulario_{kind}", "attribute_name": "record",
                        "entity_key": {"process_number": r["process_number"],
                                       "document_id": r["document_id"],
                                       **({"registration_number": r["registration_number"]} if kind == "product" else {})},
                        "value_text": r.get("product_name", r.get("document_status")),
                        "value_json": r, "language_code": "pt-BR",
                        "source_locator": {"source_url": BASE + FILES[kind], "record_number": r["record_number"]},
                        "content_hash": r["row_sha256"],
                    } for r in records[start:start + 500]])
                inserted[kind] = len(records)
    finally:
        await engine.dispose()
    return inserted


async def run(args) -> dict:
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    # All validation precedes database writes and catalogue publication.
    datasets, hashes, paths = {}, {}, {}
    for kind in FILES:
        local = getattr(args, kind + "_csv")
        print(json.dumps({"stage": "reading", "dataset": kind}), flush=True)
        content = Path(local).read_bytes() if local else await download(kind)
        datasets[kind] = parse(content, kind)
        hashes[kind] = digest(content)
        raw = output / "raw" / hashes[kind] / FILES[kind]
        raw.parent.mkdir(parents=True, exist_ok=True)
        if not raw.exists():
            temp = raw.with_suffix(".tmp")
            temp.write_bytes(content)
            os.replace(temp, raw)
        elif digest(raw.read_bytes()) != hashes[kind]:
            raise ValueError("Existing RAW checksum mismatch")
        paths[kind] = raw
        print(json.dumps({"stage": "validated", "dataset": kind, "rows": len(datasets[kind])}), flush=True)
    inserted = await import_postgres(args.database_url, datasets, paths, hashes) if args.database_url else None
    summary = write_catalogue(output / "bulario.sqlite", datasets, hashes)
    summary["postgres_assertions_inserted"] = inserted
    temp = output / "summary.tmp"
    temp.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(temp, output / "summary.json")
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--product-csv", help="Use a previously downloaded official product CSV")
    parser.add_argument("--document-csv", help="Use a previously downloaded official document CSV")
    parser.add_argument("--output", default="data/raw/bulario")
    parser.add_argument("--database-url", default=os.environ.get("DATABASE_URL"))
    args = parser.parse_args()
    try:
        print(json.dumps(asyncio.run(run(args)), ensure_ascii=False, indent=2))
    except Exception as exc:
        print(json.dumps({"status": "failed", "error": str(exc)}), file=sys.stderr)
        raise SystemExit(1) from exc


if __name__ == "__main__":
    main()
