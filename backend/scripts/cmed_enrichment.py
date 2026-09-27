from __future__ import annotations

import argparse
import asyncio
import hashlib
import html
import io
import json
import os
import re
import unicodedata
import uuid
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from typing import Any
from urllib.parse import urljoin

import httpx
import pandas as pd
from sqlalchemy import bindparam, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.db.models import (
    DosageForm,
    FieldProvenance,
    MedicationProduct,
    Presentation,
    PresentationRoute,
    Route,
    SourceAssertion,
    SourceSnapshot,
    SourceSystem,
)
from scripts.entity_resolution import normalize_name


CMED_INDEX_URL = "https://www.gov.br/anvisa/pt-br/assuntos/medicamentos/cmed/precos"
SOURCE_CODE = "CMED"
UUID_NAMESPACE = uuid.UUID("62bb6697-e111-4c2f-9ea4-f3fef52f9f22")


@dataclass(frozen=True)
class CmedSummary:
    source_url: str
    rows_read: int
    rows_matched: int
    products_enriched: int
    presentations_upserted: int
    routes_linked: int
    rows_skipped: int


def _header(value: Any) -> str:
    text = unicodedata.normalize("NFKD", str(value))
    text = "".join(char for char in text if not unicodedata.combining(char))
    text = re.sub(r"[^A-Za-z0-9]+", "_", text).strip("_").upper()
    return text


def _clean(value: Any) -> str | None:
    if value is None or pd.isna(value):
        return None
    text = re.sub(r"\s+", " ", str(value)).strip()
    if text.endswith(".0") and text[:-2].isdigit():
        text = text[:-2]
    return text or None


def normalize_registration(value: Any) -> str | None:
    cleaned = _clean(value)
    if not cleaned:
        return None
    digits = re.sub(r"\D", "", cleaned)
    return digits or None


def _first(row: dict[str, Any], *keys: str) -> str | None:
    for key in keys:
        value = _clean(row.get(key))
        if value:
            return value
    return None


def infer_dosage_form(presentation: str) -> str:
    value = f" {normalize_name(presentation).upper()} "
    patterns = (
        (("PO LIOF", "LIOF INJ"), "Pó liofilizado para solução injetável"),
        (("PO P/ SUS OR", "PO SUS OR"), "Pó para suspensão oral"),
        (("SUS OR", "SUSP OR"), "Suspensão oral"),
        (("SOL OFT",), "Solução oftálmica"),
        (("SOL OTO",), "Solução otológica"),
        (("SOL NAS",), "Solução nasal"),
        (("SOL OR",), "Solução oral"),
        (("SOL INJ", "INJ"), "Solução injetável"),
        (("COM REV",), "Comprimido revestido"),
        (("COM DISP",), "Comprimido dispersível"),
        (("COM MAST",), "Comprimido mastigável"),
        ((" COM ",), "Comprimido"),
        (("CAP DURA", " CAP "), "Cápsula"),
        ((" XPE ", "XAROPE"), "Xarope"),
        ((" CREM ", "CREME"), "Creme"),
        ((" POM ", "POMADA"), "Pomada"),
        ((" GEL ",), "Gel"),
        ((" SUP ", "SUPOS"), "Supositório"),
        ((" AER ", "AEROSSOL"), "Aerossol"),
    )
    for tokens, label in patterns:
        if any(token in value for token in tokens):
            return label
    return "Forma farmacêutica não estruturada (CMED)"


def infer_route(presentation: str) -> tuple[str, str] | None:
    value = f" {normalize_name(presentation).upper()} "
    routes = (
        ((" OFT ", "OFTAL"), ("OFT", "Oftálmica")),
        ((" OTO ", "OTOLOG"), ("OTO", "Otológica")),
        ((" NAS ", "NASAL"), ("NAS", "Nasal")),
        ((" VAG ", "VAGINAL"), ("VAG", "Vaginal")),
        ((" RET ", "RETAL"), ("RET", "Retal")),
        ((" TOP ", "TOPIC"), ("TOP", "Tópica")),
        ((" OR ", " ORAL "), ("ORAL", "Oral")),
        ((" IV ", "INTRAVEN"), ("IV", "Intravenosa")),
        ((" IM ", "INTRAMUSC"), ("IM", "Intramuscular")),
    )
    for tokens, route in routes:
        if any(token in value for token in tokens):
            return route
    return None


def _stable_uuid(kind: str, material: str) -> uuid.UUID:
    return uuid.uuid5(UUID_NAMESPACE, f"{kind}:{material}")


def _dosage_form_code(name: str) -> str:
    digest = hashlib.sha256(normalize_name(name).encode()).hexdigest()[:12].upper()
    return f"CMED_{digest}"


def _latest_xlsx_url(page_html: str) -> str:
    candidates = re.findall(
        r'href=["\']([^"\']*xls_conformidade_site_[^"\']+\.xlsx)["\']',
        page_html,
        flags=re.IGNORECASE,
    )
    if not candidates:
        raise RuntimeError("Could not discover the current CMED XLSX on the official page")
    decoded = [html.unescape(item) for item in candidates]
    return urljoin(CMED_INDEX_URL, sorted(decoded)[-1])


def load_cmed_dataframe(content: bytes) -> pd.DataFrame:
    workbook = pd.ExcelFile(io.BytesIO(content), engine="openpyxl")
    for sheet_name in workbook.sheet_names:
        probe = pd.read_excel(
            workbook,
            sheet_name=sheet_name,
            header=None,
            nrows=30,
            dtype=str,
        )
        for row_index, values in probe.iterrows():
            headers = {_header(value) for value in values if _clean(value)}
            if "REGISTRO" in headers and "APRESENTACAO" in headers:
                frame = pd.read_excel(
                    workbook,
                    sheet_name=sheet_name,
                    header=row_index,
                    dtype=str,
                )
                frame.columns = [_header(value) for value in frame.columns]
                return frame
    raise RuntimeError("CMED workbook does not contain REGISTRO/APRESENTACAO headers")


async def _download_cmed() -> tuple[str, bytes, dict[str, str]]:
    override = os.getenv("CMED_XLSX_URL")
    timeout = httpx.Timeout(120.0, connect=30.0)
    headers = {"User-Agent": "nursing-clinical-data-pipeline/1.1"}
    async with httpx.AsyncClient(
        timeout=timeout,
        follow_redirects=True,
        headers=headers,
    ) as client:
        if override:
            source_url = override
        else:
            page = await client.get(CMED_INDEX_URL)
            page.raise_for_status()
            source_url = _latest_xlsx_url(page.text)
        response = await client.get(source_url)
        response.raise_for_status()
        return source_url, response.content, dict(response.headers)


def _match_product(
    registration: str,
    products: dict[str, MedicationProduct],
) -> MedicationProduct | None:
    exact = products.get(registration)
    if exact is not None:
        return exact
    if len(registration) > 9:
        prefix = products.get(registration[:9])
        if prefix is not None:
            return prefix
    return None


async def enrich_cmed(
    session: AsyncSession,
    *,
    source_url: str,
    content: bytes,
    response_headers: dict[str, str] | None = None,
) -> CmedSummary:
    frame = load_cmed_dataframe(content)
    checksum = hashlib.sha256(content).hexdigest()

    source_stmt = (
        pg_insert(SourceSystem)
        .values(
            id=_stable_uuid("source", SOURCE_CODE),
            code=SOURCE_CODE,
            name="Câmara de Regulação do Mercado de Medicamentos - CMED",
            country_code="BR",
            base_url=CMED_INDEX_URL,
            authority_level=95,
            is_active=True,
        )
        .on_conflict_do_update(
            index_elements=[SourceSystem.code],
            set_={
                "name": "Câmara de Regulação do Mercado de Medicamentos - CMED",
                "base_url": CMED_INDEX_URL,
                "authority_level": 95,
                "is_active": True,
            },
        )
        .returning(SourceSystem.id)
    )
    source_id = (await session.execute(source_stmt)).scalar_one()

    existing_snapshot = await session.scalar(
        select(SourceSnapshot).where(
            SourceSnapshot.source_system_id == source_id,
            SourceSnapshot.checksum_sha256 == checksum,
        )
    )
    if existing_snapshot is None:
        snapshot = SourceSnapshot(
            id=_stable_uuid("snapshot", f"{SOURCE_CODE}:{checksum}"),
            source_system_id=source_id,
            dataset_name="Lista de Preços de Medicamentos - CMED",
            source_version=os.path.basename(source_url),
            retrieved_at=datetime.now(timezone.utc),
            checksum_sha256=checksum,
            raw_object_uri=source_url,
            etl_version="cmed-enrichment-v1",
            schema_version="cmed-price-list",
            snapshot_metadata={
                "content_length": len(content),
                "last_modified": (response_headers or {}).get("last-modified"),
            },
        )
        session.add(snapshot)
        await session.flush()
        snapshot_id = snapshot.id
    else:
        snapshot_id = existing_snapshot.id

    product_rows = list((await session.scalars(select(MedicationProduct))).all())
    products: dict[str, MedicationProduct] = {}
    for product in product_rows:
        normalized = normalize_registration(product.anvisa_registration_number)
        if normalized:
            products[normalized] = product

    # Any presentation absent from the new CMED list must not remain silently active.
    await session.execute(
        update(Presentation)
        .where(Presentation.external_presentation_code.like("CMED:%"))
        .values(is_active=False)
    )

    assertion_rows: list[dict[str, Any]] = []
    presentation_rows: list[dict[str, Any]] = []
    provenance_rows: list[dict[str, Any]] = []
    dosage_forms: dict[str, dict[str, Any]] = {}
    routes: dict[str, dict[str, Any]] = {}
    route_links: list[dict[str, Any]] = []
    product_enrichment: dict[uuid.UUID, dict[str, Any]] = {}

    rows_read = rows_matched = rows_skipped = 0

    for row_number, series in frame.iterrows():
        rows_read += 1
        row = {key: _clean(value) for key, value in series.to_dict().items()}
        registration = normalize_registration(row.get("REGISTRO"))
        presentation_text = _first(row, "APRESENTACAO")
        if not registration or not presentation_text:
            rows_skipped += 1
            continue

        product = _match_product(registration, products)
        if product is None or not product.is_active:
            rows_skipped += 1
            continue
        rows_matched += 1

        ggrem = _first(row, "CODIGO_GGREM", "COD_GGREM")
        ean = _first(row, "EAN_1", "EAN1", "EAN")
        material = ggrem or ean or hashlib.sha256(
            f"{registration}|{presentation_text}".encode()
        ).hexdigest()[:24]
        external_code = f"CMED:{material}"
        presentation_id = _stable_uuid(
            "presentation",
            f"{product.id}:{external_code}",
        )
        assertion_id = _stable_uuid(
            "assertion",
            f"{snapshot_id}:{external_code}",
        )

        dosage_form_name = infer_dosage_form(presentation_text)
        dosage_key = normalize_name(dosage_form_name)
        dosage_form_id = _stable_uuid("dosage-form", dosage_key)
        dosage_forms[dosage_key] = {
            "id": dosage_form_id,
            "code": _dosage_form_code(dosage_form_name),
            "name": dosage_form_name,
            "normalized_name": dosage_key,
            "is_active": True,
        }

        therapeutic_class = _first(row, "CLASSE_TERAPEUTICA")
        product_type = _first(
            row,
            "TIPO_DE_PRODUTO_STATUS_DO_PRODUTO",
            "TIPO_DE_PRODUTO",
        )
        previous = product_enrichment.setdefault(
            product.id,
            {
                "p_id": product.id,
                "therapeutic_class": None,
                "product_type": None,
            },
        )
        previous["therapeutic_class"] = (
            previous["therapeutic_class"] or therapeutic_class
        )
        previous["product_type"] = previous["product_type"] or product_type

        source_payload = {
            "REGISTRO": registration,
            "PRODUTO": _first(row, "PRODUTO"),
            "APRESENTACAO": presentation_text,
            "CODIGO_GGREM": ggrem,
            "EAN_1": ean,
            "CLASSE_TERAPEUTICA": therapeutic_class,
            "TIPO_DE_PRODUTO": product_type,
        }
        assertion_rows.append(
            {
                "id": assertion_id,
                "source_snapshot_id": snapshot_id,
                "external_record_id": external_code[:255],
                "entity_type": "cmed_presentation",
                "entity_key": {
                    "registration_number": registration,
                    "external_presentation_code": external_code,
                },
                "attribute_name": "record",
                "value_text": presentation_text,
                "value_json": source_payload,
                "language_code": "pt-BR",
                "source_locator": {
                    "url": source_url,
                    "row": int(row_number) + 1,
                },
                "content_hash": hashlib.sha256(
                    json.dumps(
                        source_payload,
                        ensure_ascii=False,
                        sort_keys=True,
                    ).encode()
                ).hexdigest(),
            }
        )
        presentation_rows.append(
            {
                "id": presentation_id,
                "medication_product_id": product.id,
                "dosage_form_id": dosage_form_id,
                "external_presentation_code": external_code,
                "description": presentation_text,
                "strength_text": presentation_text,
                "concentration_value": None,
                "concentration_unit": None,
                "concentration_denominator_value": None,
                "concentration_denominator_unit": None,
                "package_quantity": None,
                "package_unit": None,
                "calculation_ready": False,
                "regulatory_status": product.regulatory_status,
                "is_active": True,
            }
        )

        for field_name in ("description", "strength_text", "dosage_form_id"):
            provenance_rows.append(
                {
                    "id": _stable_uuid(
                        "provenance",
                        f"{assertion_id}:{presentation_id}:{field_name}",
                    ),
                    "source_assertion_id": assertion_id,
                    "target_layer": "canonical",
                    "target_entity_type": "presentation",
                    "target_entity_id": presentation_id,
                    "target_field_name": field_name,
                    "is_primary": True,
                    "confidence": 1,
                    "review_status": "source_validated",
                    "reviewed_by": "CMED_IMPORT_V1",
                    "reviewed_at": datetime.now(timezone.utc),
                    "note": "Official CMED presentation list.",
                }
            )

        route = infer_route(presentation_text)
        if route is not None:
            route_code, route_name = route
            route_key = normalize_name(route_name)
            route_id = _stable_uuid("route", route_key)
            routes[route_key] = {
                "id": route_id,
                "code": route_code,
                "name": route_name,
                "normalized_name": route_key,
                "is_active": True,
            }
            route_links.append(
                {
                    "presentation_id": presentation_id,
                    "route_id": route_id,
                }
            )

    if dosage_forms:
        await session.execute(
            pg_insert(DosageForm)
            .values(list(dosage_forms.values()))
            .on_conflict_do_update(
                index_elements=[DosageForm.normalized_name],
                set_={"name": pg_insert(DosageForm).excluded.name, "is_active": True},
            )
        )
    if routes:
        await session.execute(
            pg_insert(Route)
            .values(list(routes.values()))
            .on_conflict_do_update(
                index_elements=[Route.normalized_name],
                set_={"name": pg_insert(Route).excluded.name, "is_active": True},
            )
        )
    if assertion_rows:
        stmt = pg_insert(SourceAssertion).values(assertion_rows)
        await session.execute(
            stmt.on_conflict_do_update(
                index_elements=[SourceAssertion.id],
                set_={
                    "value_text": stmt.excluded.value_text,
                    "value_json": stmt.excluded.value_json,
                    "source_locator": stmt.excluded.source_locator,
                    "content_hash": stmt.excluded.content_hash,
                },
            )
        )
    if presentation_rows:
        stmt = pg_insert(Presentation).values(presentation_rows)
        await session.execute(
            stmt.on_conflict_do_update(
                index_elements=[
                    Presentation.medication_product_id,
                    Presentation.external_presentation_code,
                ],
                set_={
                    "dosage_form_id": stmt.excluded.dosage_form_id,
                    "description": stmt.excluded.description,
                    "strength_text": stmt.excluded.strength_text,
                    "regulatory_status": stmt.excluded.regulatory_status,
                    "is_active": True,
                },
            )
        )
    if route_links:
        await session.execute(
            pg_insert(PresentationRoute)
            .values(route_links)
            .on_conflict_do_nothing(
                index_elements=[
                    PresentationRoute.presentation_id,
                    PresentationRoute.route_id,
                ]
            )
        )
    if provenance_rows:
        await session.execute(
            pg_insert(FieldProvenance)
            .values(provenance_rows)
            .on_conflict_do_nothing(
                index_elements=[
                    FieldProvenance.target_layer,
                    FieldProvenance.target_entity_type,
                    FieldProvenance.target_entity_id,
                    FieldProvenance.target_field_name,
                    FieldProvenance.source_assertion_id,
                ]
            )
        )
    if product_enrichment:
        table = MedicationProduct.__table__
        stmt = (
            table.update()
            .where(table.c.id == bindparam("p_id"))
            .values(
                therapeutic_class=bindparam("therapeutic_class"),
                product_type=bindparam("product_type"),
            )
        )
        await session.execute(stmt, list(product_enrichment.values()))

    await session.flush()
    return CmedSummary(
        source_url=source_url,
        rows_read=rows_read,
        rows_matched=rows_matched,
        products_enriched=len(product_enrichment),
        presentations_upserted=len(presentation_rows),
        routes_linked=len(route_links),
        rows_skipped=rows_skipped,
    )


async def async_main(args: argparse.Namespace) -> int:
    database_url = args.database_url or os.getenv("DATABASE_URL")
    if not database_url:
        raise RuntimeError("DATABASE_URL is required")
    if not database_url.startswith("postgresql+asyncpg://"):
        raise RuntimeError("DATABASE_URL must use the postgresql+asyncpg driver")

    source_url, content, headers = await _download_cmed()
    engine = create_async_engine(database_url, pool_pre_ping=True)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    try:
        async with session_factory() as session:
            async with session.begin():
                summary = await enrich_cmed(
                    session,
                    source_url=source_url,
                    content=content,
                    response_headers=headers,
                )
        print(json.dumps(asdict(summary), ensure_ascii=False, indent=2))
        return 0
    finally:
        await engine.dispose()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Enrich canonical medications and presentations from CMED."
    )
    parser.add_argument("--database-url", default=None, help="Overrides DATABASE_URL.")
    return parser


def main() -> int:
    return asyncio.run(async_main(build_parser().parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
