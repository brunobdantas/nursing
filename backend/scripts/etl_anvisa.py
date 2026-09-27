from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import os
import re
import sys
import unicodedata
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Any, Iterable

import httpx
import pandas as pd
from sqlalchemy import insert, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine


BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.db.models import SourceAssertion, SourceSnapshot, SourceSystem  # noqa: E402


ANVISA_DATASET_NAME = "DADOS_ABERTOS_MEDICAMENTOS.csv"
ANVISA_DATASET_URL = (
    "https://dados.anvisa.gov.br/dados/DADOS_ABERTOS_MEDICAMENTOS.csv"
)
ANVISA_BASE_URL = "https://dados.anvisa.gov.br/dados/"
ANVISA_TERMS_URL = "https://www.gov.br/anvisa/pt-br/acessoainformacao/dadosabertos"
ETL_VERSION = "anvisa-medications-etl/1.0.0"
SCHEMA_VERSION = "anvisa-open-data-medications/staging-v1"


@dataclass(frozen=True)
class DownloadedDataset:
    content: bytes
    source_url: str
    retrieved_at: datetime
    etag: str | None
    last_modified: datetime | None
    content_type: str | None


@dataclass(frozen=True)
class IngestionSummary:
    snapshot_id: uuid.UUID
    checksum_sha256: str
    rows: int
    assertions_inserted: int
    already_ingested: bool


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _json_hash(value: Any) -> str:
    encoded = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _parse_http_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        parsed = parsedate_to_datetime(value)
    except (TypeError, ValueError, OverflowError):
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _normalize_header(value: str) -> str:
    text = unicodedata.normalize("NFKD", value)
    text = "".join(char for char in text if not unicodedata.combining(char))
    text = re.sub(r"[^A-Za-z0-9]+", "_", text.strip()).strip("_")
    return text.upper()


def _build_column_map(columns: Iterable[str]) -> dict[str, str]:
    """Map original column names to collision-safe normalized names."""

    result: dict[str, str] = {}
    used: dict[str, int] = {}
    for original in columns:
        base = _normalize_header(str(original)) or "UNNAMED"
        count = used.get(base, 0) + 1
        used[base] = count
        normalized = base if count == 1 else f"{base}_{count}"
        result[str(original)] = normalized
    return result


def _clean_scalar(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _first(row: dict[str, str | None], *keys: str) -> str | None:
    for key in keys:
        value = row.get(key)
        if value:
            return value
    return None


def _validate_dataset_shape(normalized_columns: set[str]) -> None:
    """
    Fail closed on a material upstream schema break.

    The staging layer preserves all columns, but we still require enough identity
    fields to know we are processing the medication-registration dataset rather
    than a different CSV accidentally served at the same location.
    """

    identity_groups = {
        "registration": {"NUMERO_REGISTRO_PRODUTO", "REGISTRO"},
        "product_name": {"NOME_PRODUTO", "PRODUTO", "NOME_COMERCIAL"},
        "active_ingredient": {"PRINCIPIO_ATIVO"},
    }

    missing = [
        label
        for label, aliases in identity_groups.items()
        if not (normalized_columns & aliases)
    ]
    if missing:
        raise RuntimeError(
            "ANVISA dataset schema is not recognized. Missing identity groups: "
            + ", ".join(missing)
        )


def _decode_csv(content: bytes) -> tuple[str, str]:
    """Decode without modifying the raw bytes persisted in RAW storage."""

    for encoding in ("utf-8-sig", "latin-1"):
        try:
            return content.decode(encoding), encoding
        except UnicodeDecodeError:
            continue
    raise RuntimeError("Unable to decode ANVISA CSV using supported encodings")


def _load_dataframe(content: bytes) -> tuple[pd.DataFrame, str, dict[str, str]]:
    text, encoding = _decode_csv(content)
    from io import StringIO

    frame = pd.read_csv(
        StringIO(text),
        sep=";",
        dtype=str,
        keep_default_na=False,
        na_filter=False,
        on_bad_lines="error",
    )
    if frame.empty:
        raise RuntimeError("ANVISA dataset is empty; ingestion aborted")

    column_map = _build_column_map([str(column) for column in frame.columns])
    _validate_dataset_shape(set(column_map.values()))
    return frame, encoding, column_map


async def _download(url: str) -> DownloadedDataset:
    transport = httpx.AsyncHTTPTransport(retries=3)
    timeout = httpx.Timeout(connect=20.0, read=120.0, write=30.0, pool=30.0)

    async with httpx.AsyncClient(
        transport=transport,
        timeout=timeout,
        follow_redirects=True,
        headers={"User-Agent": "nursing-mvp-anvisa-etl/1.0"},
    ) as client:
        response = await client.get(url)
        response.raise_for_status()
        content = response.content

    if not content:
        raise RuntimeError("ANVISA download returned an empty body")

    return DownloadedDataset(
        content=content,
        source_url=str(response.url),
        retrieved_at=datetime.now(timezone.utc),
        etag=response.headers.get("etag"),
        last_modified=_parse_http_datetime(response.headers.get("last-modified")),
        content_type=response.headers.get("content-type"),
    )


def _load_local(path: Path, source_url: str) -> DownloadedDataset:
    content = path.read_bytes()
    if not content:
        raise RuntimeError(f"Local CSV is empty: {path}")
    stat = path.stat()
    return DownloadedDataset(
        content=content,
        source_url=source_url,
        retrieved_at=datetime.now(timezone.utc),
        etag=None,
        last_modified=datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc),
        content_type="text/csv",
    )


def _persist_raw(content: bytes, raw_dir: Path, checksum: str) -> Path:
    now = datetime.now(timezone.utc)
    target_dir = raw_dir / f"{now:%Y}" / f"{now:%m}" / f"{now:%d}"
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / f"{ANVISA_DATASET_NAME.removesuffix('.csv')}_{checksum}.csv"
    if not target.exists():
        target.write_bytes(content)
    return target.resolve()


def _record_payload(
    raw_row: dict[str, Any],
    column_map: dict[str, str],
) -> tuple[dict[str, str | None], dict[str, Any]]:
    raw_json = {str(key): (None if value is None else str(value)) for key, value in raw_row.items()}
    normalized = {
        column_map[str(key)]: _clean_scalar(value)
        for key, value in raw_row.items()
    }
    payload = {
        "raw": raw_json,
        "normalized": normalized,
    }
    return normalized, payload


def _entity_key(normalized: dict[str, str | None], row_hash: str) -> dict[str, str]:
    registration = _first(normalized, "NUMERO_REGISTRO_PRODUTO", "REGISTRO")
    process_number = _first(normalized, "NUMERO_PROCESSO", "PROCESSO")
    product_name = _first(normalized, "NOME_PRODUTO", "PRODUTO", "NOME_COMERCIAL")

    key: dict[str, str] = {}
    if registration:
        key["registration_number"] = registration
    if process_number:
        key["process_number"] = process_number
    if product_name:
        key["product_name"] = product_name
    if not key:
        key["row_hash"] = row_hash
    return key


def _external_record_id(
    normalized: dict[str, str | None],
    row_number: int,
    row_hash: str,
) -> str:
    registration = _first(normalized, "NUMERO_REGISTRO_PRODUTO", "REGISTRO")
    process_number = _first(normalized, "NUMERO_PROCESSO", "PROCESSO")

    parts: list[str] = []
    if registration:
        parts.append(f"reg:{registration}")
    if process_number:
        parts.append(f"proc:{process_number}")
    if parts:
        return "|".join(parts)[:255]
    return f"row:{row_number}:{row_hash[:24]}"


def _display_text(normalized: dict[str, str | None]) -> str | None:
    product = _first(normalized, "NOME_PRODUTO", "PRODUTO", "NOME_COMERCIAL")
    ingredient = _first(normalized, "PRINCIPIO_ATIVO")
    if product and ingredient:
        return f"{product} — {ingredient}"
    return product or ingredient


def _chunks(values: list[dict[str, Any]], size: int) -> Iterable[list[dict[str, Any]]]:
    for start in range(0, len(values), size):
        yield values[start : start + size]


async def _get_or_create_source_system(session: AsyncSession) -> SourceSystem:
    source = await session.scalar(
        select(SourceSystem).where(SourceSystem.code == "ANVISA")
    )
    if source is not None:
        # Keep source metadata current without changing its identity.
        source.name = "Agência Nacional de Vigilância Sanitária"
        source.country_code = "BR"
        source.base_url = ANVISA_BASE_URL
        source.terms_url = ANVISA_TERMS_URL
        source.authority_level = 100
        source.is_active = True
        return source

    source = SourceSystem(
        id=uuid.uuid4(),
        code="ANVISA",
        name="Agência Nacional de Vigilância Sanitária",
        country_code="BR",
        base_url=ANVISA_BASE_URL,
        terms_url=ANVISA_TERMS_URL,
        authority_level=100,
        is_active=True,
    )
    session.add(source)
    await session.flush()
    return source


async def ingest_dataset(
    *,
    database_url: str,
    dataset: DownloadedDataset,
    raw_dir: Path,
    batch_size: int = 1000,
) -> IngestionSummary:
    checksum = _sha256(dataset.content)
    raw_path = _persist_raw(dataset.content, raw_dir, checksum)

    engine = create_async_engine(database_url, pool_pre_ping=True)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    try:
        async with session_factory() as session:
            async with session.begin():
                source_system = await _get_or_create_source_system(session)

                existing = await session.scalar(
                    select(SourceSnapshot).where(
                        SourceSnapshot.source_system_id == source_system.id,
                        SourceSnapshot.checksum_sha256 == checksum,
                    )
                )
                if existing is not None:
                    return IngestionSummary(
                        snapshot_id=existing.id,
                        checksum_sha256=checksum,
                        rows=int((existing.snapshot_metadata or {}).get("row_count", 0)),
                        assertions_inserted=0,
                        already_ingested=True,
                    )

                frame, detected_encoding, column_map = _load_dataframe(dataset.content)
                normalized_columns = list(column_map.values())

                snapshot = SourceSnapshot(
                    id=uuid.uuid4(),
                    source_system_id=source_system.id,
                    dataset_name=ANVISA_DATASET_NAME,
                    source_version=(
                        dataset.etag
                        or (
                            dataset.last_modified.isoformat()
                            if dataset.last_modified
                            else checksum[:16]
                        )
                    ),
                    source_last_modified_at=dataset.last_modified,
                    retrieved_at=dataset.retrieved_at,
                    checksum_sha256=checksum,
                    raw_object_uri=raw_path.as_uri(),
                    etl_version=ETL_VERSION,
                    schema_version=SCHEMA_VERSION,
                    snapshot_metadata={
                        "source_url": dataset.source_url,
                        "content_type": dataset.content_type,
                        "etag": dataset.etag,
                        "encoding_detected": detected_encoding,
                        "delimiter": ";",
                        "row_count": int(len(frame)),
                        "columns_original": [str(column) for column in frame.columns],
                        "columns_normalized": normalized_columns,
                    },
                )
                session.add(snapshot)
                await session.flush()

                rows_to_insert: list[dict[str, Any]] = []
                assertions_inserted = 0

                # CSV row 1 is the header, so data begins at physical line 2.
                for offset, raw_row in enumerate(
                    frame.to_dict(orient="records"),
                    start=2,
                ):
                    normalized, payload = _record_payload(raw_row, column_map)
                    row_hash = _json_hash(payload["normalized"])
                    rows_to_insert.append(
                        {
                            "id": uuid.uuid4(),
                            "source_snapshot_id": snapshot.id,
                            "external_record_id": _external_record_id(
                                normalized, offset, row_hash
                            ),
                            "entity_type": "anvisa_medication_record",
                            "entity_key": _entity_key(normalized, row_hash),
                            "attribute_name": "record",
                            "value_text": _display_text(normalized),
                            "value_json": payload,
                            "unit": None,
                            "language_code": "pt-BR",
                            "source_locator": {
                                "dataset": ANVISA_DATASET_NAME,
                                "row_number": offset,
                                "source_url": dataset.source_url,
                            },
                            "content_hash": row_hash,
                        }
                    )

                    if len(rows_to_insert) >= batch_size:
                        await session.execute(insert(SourceAssertion), rows_to_insert)
                        assertions_inserted += len(rows_to_insert)
                        rows_to_insert.clear()

                if rows_to_insert:
                    await session.execute(insert(SourceAssertion), rows_to_insert)
                    assertions_inserted += len(rows_to_insert)

                summary = IngestionSummary(
                    snapshot_id=snapshot.id,
                    checksum_sha256=checksum,
                    rows=int(len(frame)),
                    assertions_inserted=assertions_inserted,
                    already_ingested=False,
                )

            return summary
    finally:
        await engine.dispose()


async def async_main(args: argparse.Namespace) -> int:
    database_url = args.database_url or os.getenv("DATABASE_URL")
    if not database_url:
        raise RuntimeError(
            "DATABASE_URL is required, e.g. "
            "postgresql+asyncpg://user:password@localhost:5432/nursing_mvp"
        )
    if not database_url.startswith("postgresql+asyncpg://"):
        raise RuntimeError("DATABASE_URL must use the postgresql+asyncpg driver")

    if args.csv_path:
        dataset = _load_local(Path(args.csv_path), args.source_url)
    else:
        dataset = await _download(args.source_url)

    summary = await ingest_dataset(
        database_url=database_url,
        dataset=dataset,
        raw_dir=Path(args.raw_dir),
        batch_size=args.batch_size,
    )

    print(
        json.dumps(
            {
                "snapshot_id": str(summary.snapshot_id),
                "checksum_sha256": summary.checksum_sha256,
                "rows": summary.rows,
                "assertions_inserted": summary.assertions_inserted,
                "already_ingested": summary.already_ingested,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Ingest ANVISA open medication registrations into RAW/STAGING."
    )
    parser.add_argument(
        "--database-url",
        default=None,
        help="Overrides DATABASE_URL.",
    )
    parser.add_argument(
        "--source-url",
        default=ANVISA_DATASET_URL,
        help="ANVISA CSV URL.",
    )
    parser.add_argument(
        "--csv-path",
        default=None,
        help="Optional local CSV for deterministic/replay ingestion.",
    )
    parser.add_argument(
        "--raw-dir",
        default="data/raw/anvisa",
        help="Directory used as MVP immutable RAW object storage.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=1000,
        help="STAGING insert batch size.",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if args.batch_size < 1:
        raise SystemExit("--batch-size must be >= 1")
    return asyncio.run(async_main(args))


if __name__ == "__main__":
    raise SystemExit(main())
