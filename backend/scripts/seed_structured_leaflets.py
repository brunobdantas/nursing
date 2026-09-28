from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import uuid
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass
from typing import Final

import httpx
from sqlalchemy import delete, func, or_, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.db.models import (
    ActiveIngredient,
    MedicationLeafletLink,
    MedicationProduct,
    MedicationProductIngredient,
    ProfessionalLeaflet,
)


SEED_ID: Final = "HOTFIX151_DAILYMED_SPL_SEED"
CLINICAL_VERSION: Final = "hotfix-1.5.1-1.0.0"
SOURCE_NAME: Final = "DailyMed / FDA SPL"
SOURCE_LANGUAGE: Final = "en-US"
UUID_NAMESPACE: Final = uuid.UUID("13a7c42d-a36d-4dd3-a079-b870f480e571")
DAILYMED_API: Final = "https://dailymed.nlm.nih.gov/dailymed/services/v2/spls"


@dataclass(frozen=True)
class LeafletSpec:
    key: str
    aliases: tuple[str, ...]
    set_id: str


@dataclass(frozen=True)
class ParsedLeaflet:
    source_version: str
    source_effective_date: str | None
    sections: dict[str, str | None]


@dataclass(frozen=True)
class SeedSummary:
    documents_fetched: int
    structured_documents: int
    medication_links: int
    products_without_safe_reference: tuple[str, ...]


LEAFLETS: Final = (
    LeafletSpec(
        key="norepinephrine",
        aliases=(
            "hemitartarato de norepinefrina",
            "hemitartarato de norepinefrina monoidratada",
        ),
        set_id="109aa5e6-4e42-4131-97b0-f24d3a4cb4e8",
    ),
    LeafletSpec(
        key="amiodarone",
        aliases=("cloridrato de amiodarona",),
        set_id="304d0be4-0c13-4dbb-8ffb-b2e7caa7fb1e",
    ),
    LeafletSpec(
        key="ceftriaxone",
        aliases=("ceftriaxona",),
        set_id="ff8e830a-c288-46fb-9e19-ec2017943c07",
    ),
    LeafletSpec(
        key="fentanyl",
        aliases=("citrato de fentanila", "fentanila", "fentanil"),
        set_id="c5d40297-b769-48cc-9f84-f98b7a333507",
    ),
    LeafletSpec(
        key="propofol",
        aliases=("propofol",),
        set_id="de351d5f-581d-4768-a4af-fbd8e5bce264",
    ),
)

SECTION_FIELDS: Final = (
    "indications_text",
    "dosage_administration_text",
    "contraindications_text",
    "warnings_precautions_text",
    "adverse_reactions_text",
    "drug_interactions_text",
    "specific_populations_text",
    "overdosage_text",
    "description_text",
    "clinical_pharmacology_text",
    "how_supplied_storage_text",
    "patient_counseling_text",
)


def _stable_uuid(kind: str, material: str) -> uuid.UUID:
    return uuid.uuid5(UUID_NAMESPACE, f"{kind}:{material}")


def _local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _normalize_spaces(value: str) -> str:
    return re.sub(r"[ \t\r\f\v]+", " ", value).strip()


def _render_text(element: ET.Element) -> str:
    """Render SPL narrative to compact plain text while preserving block boundaries."""
    blocks = {
        "paragraph",
        "p",
        "item",
        "list",
        "table",
        "tr",
        "td",
        "th",
        "caption",
        "br",
    }
    parts: list[str] = []

    def visit(node: ET.Element) -> None:
        if node.text and node.text.strip():
            parts.append(node.text)
        for child in node:
            child_name = _local_name(child.tag).casefold()
            if child_name in blocks:
                parts.append("\n")
            visit(child)
            if child_name in blocks:
                parts.append("\n")
            if child.tail and child.tail.strip():
                parts.append(child.tail)

    visit(element)
    raw = "".join(parts)
    lines = [_normalize_spaces(line) for line in raw.splitlines()]
    compact: list[str] = []
    for line in lines:
        if not line:
            if compact and compact[-1] != "":
                compact.append("")
            continue
        compact.append(line)
    return "\n".join(compact).strip()


def _direct_child(element: ET.Element, name: str) -> ET.Element | None:
    for child in element:
        if _local_name(child.tag) == name:
            return child
    return None


def _metadata_value(root: ET.Element, tag_name: str) -> str | None:
    for element in root.iter():
        if _local_name(element.tag) != tag_name:
            continue
        value = element.attrib.get("value")
        if value and value.strip():
            return value.strip()
    return None


def _field_for_title(title: str) -> str | None:
    normalized = re.sub(r"\s+", " ", title).strip().upper()
    mappings = (
        ("INDICATIONS AND USAGE", "indications_text"),
        ("DOSAGE AND ADMINISTRATION", "dosage_administration_text"),
        ("CONTRAINDICATIONS", "contraindications_text"),
        ("WARNINGS AND PRECAUTIONS", "warnings_precautions_text"),
        ("WARNINGS", "warnings_precautions_text"),
        ("ADVERSE REACTIONS", "adverse_reactions_text"),
        ("DRUG INTERACTIONS", "drug_interactions_text"),
        ("USE IN SPECIFIC POPULATIONS", "specific_populations_text"),
        ("OVERDOSAGE", "overdosage_text"),
        ("DESCRIPTION", "description_text"),
        ("CLINICAL PHARMACOLOGY", "clinical_pharmacology_text"),
        ("HOW SUPPLIED/STORAGE AND HANDLING", "how_supplied_storage_text"),
        ("HOW SUPPLIED", "how_supplied_storage_text"),
        ("PATIENT COUNSELING INFORMATION", "patient_counseling_text"),
    )
    for marker, field in mappings:
        if marker in normalized:
            return field
    return None


def parse_spl(xml_bytes: bytes) -> ParsedLeaflet:
    root = ET.fromstring(xml_bytes)
    source_version = _metadata_value(root, "versionNumber") or "unknown"
    effective_date = _metadata_value(root, "effectiveTime")

    collected: dict[str, list[str]] = {field: [] for field in SECTION_FIELDS}
    for section in root.iter():
        if _local_name(section.tag) != "section":
            continue
        title_element = _direct_child(section, "title")
        if title_element is None:
            continue
        title = _render_text(title_element)
        field = _field_for_title(title)
        if field is None:
            continue

        text_element = _direct_child(section, "text")
        if text_element is not None:
            narrative = _render_text(text_element)
        else:
            narrative = _render_text(section)
            # Only the fallback can contain the section title itself.
            title_prefix = _normalize_spaces(title)
            if narrative.upper().startswith(title_prefix.upper()):
                narrative = narrative[len(title_prefix):].lstrip(" \n:-")

        if not narrative:
            continue

        if narrative not in collected[field]:
            collected[field].append(narrative)

    sections = {
        field: "\n\n".join(values).strip() or None
        for field, values in collected.items()
    }
    populated = sum(1 for value in sections.values() if value)
    if populated < 3:
        raise ValueError(
            "DailyMed SPL did not expose enough structured clinical sections "
            f"(found {populated})."
        )

    return ParsedLeaflet(
        source_version=source_version,
        source_effective_date=effective_date,
        sections=sections,
    )


async def _fetch_leaflet(client: httpx.AsyncClient, spec: LeafletSpec) -> ParsedLeaflet:
    url = f"{DAILYMED_API}/{spec.set_id}.xml"
    response = await client.get(url)
    response.raise_for_status()
    return parse_spl(response.content)


async def _ingredient_ids_for_aliases(
    session: AsyncSession,
    aliases: tuple[str, ...],
) -> set[uuid.UUID]:
    clauses = [
        ActiveIngredient.normalized_name.ilike(f"%{alias}%")
        for alias in aliases
    ]
    return set(
        (
            await session.scalars(
                select(ActiveIngredient.id).where(
                    ActiveIngredient.is_active.is_(True),
                    or_(*clauses),
                )
            )
        ).all()
    )


async def _single_ingredient_products(
    session: AsyncSession,
    ingredient_ids: set[uuid.UUID],
) -> list[MedicationProduct]:
    if not ingredient_ids:
        return []

    matching_product_ids = (
        select(MedicationProductIngredient.medication_product_id)
        .join(
            MedicationProduct,
            MedicationProduct.id == MedicationProductIngredient.medication_product_id,
        )
        .where(
            MedicationProduct.is_active.is_(True),
            MedicationProductIngredient.active_ingredient_id.in_(ingredient_ids),
        )
        .group_by(MedicationProductIngredient.medication_product_id)
    )

    # A public SPL is linked only to single-active-ingredient products. This avoids
    # silently applying a monotherapy label to a combination product.
    single_ingredient_product_ids = (
        select(MedicationProductIngredient.medication_product_id)
        .where(
            MedicationProductIngredient.medication_product_id.in_(matching_product_ids)
        )
        .group_by(MedicationProductIngredient.medication_product_id)
        .having(func.count(MedicationProductIngredient.active_ingredient_id) == 1)
    )

    return list(
        (
            await session.scalars(
                select(MedicationProduct)
                .where(
                    MedicationProduct.is_active.is_(True),
                    MedicationProduct.id.in_(single_ingredient_product_ids),
                )
                .order_by(MedicationProduct.id)
            )
        ).all()
    )


async def _upsert_leaflet(
    session: AsyncSession,
    *,
    spec: LeafletSpec,
    parsed: ParsedLeaflet,
) -> uuid.UUID:
    await session.execute(
        update(ProfessionalLeaflet)
        .where(
            ProfessionalLeaflet.source_name == SOURCE_NAME,
            ProfessionalLeaflet.source_document_id == spec.set_id,
            ProfessionalLeaflet.source_version != parsed.source_version,
            ProfessionalLeaflet.reviewed_by == SEED_ID,
        )
        .values(is_current=False, updated_at=func.now())
    )

    leaflet_id = _stable_uuid(
        "professional-leaflet",
        f"{spec.set_id}:{parsed.source_version}",
    )
    source_url = (
        "https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?"
        f"setid={spec.set_id}"
    )
    values = {
        "id": leaflet_id,
        "source_name": SOURCE_NAME,
        "source_document_id": spec.set_id,
        "source_version": parsed.source_version,
        "source_language": SOURCE_LANGUAGE,
        "source_url": source_url,
        "source_effective_date": parsed.source_effective_date,
        **parsed.sections,
        "review_status": "public_label_verified",
        "reviewed_by": SEED_ID,
        "reviewed_at": func.now(),
        "clinical_version": CLINICAL_VERSION,
        "is_current": True,
    }
    stmt = (
        pg_insert(ProfessionalLeaflet)
        .values(**values)
        .on_conflict_do_update(
            index_elements=[
                ProfessionalLeaflet.source_name,
                ProfessionalLeaflet.source_document_id,
                ProfessionalLeaflet.source_version,
            ],
            set_={
                key: value
                for key, value in values.items()
                if key != "id"
            }
            | {"updated_at": func.now()},
        )
        .returning(ProfessionalLeaflet.id)
    )
    return (await session.execute(stmt)).scalar_one()


async def seed_structured_leaflets(
    session: AsyncSession,
    *,
    client: httpx.AsyncClient,
) -> SeedSummary:
    await session.execute(
        delete(MedicationLeafletLink).where(
            MedicationLeafletLink.reviewed_by == SEED_ID
        )
    )

    fetched = 0
    structured = 0
    links = 0
    missing: list[str] = []

    for spec in LEAFLETS:
        parsed = await _fetch_leaflet(client, spec)
        fetched += 1
        leaflet_id = await _upsert_leaflet(session, spec=spec, parsed=parsed)
        structured += 1

        ingredient_ids = await _ingredient_ids_for_aliases(session, spec.aliases)
        products = await _single_ingredient_products(session, ingredient_ids)
        if not products:
            missing.append(spec.key)
            continue

        for product in products:
            stmt = (
                pg_insert(MedicationLeafletLink)
                .values(
                    medication_product_id=product.id,
                    professional_leaflet_id=leaflet_id,
                    relation_type="active_ingredient_reference",
                    review_status="public_label_verified",
                    reviewed_by=SEED_ID,
                    reviewed_at=func.now(),
                    is_current=True,
                )
                .on_conflict_do_update(
                    index_elements=[
                        MedicationLeafletLink.medication_product_id,
                        MedicationLeafletLink.professional_leaflet_id,
                    ],
                    set_={
                        "relation_type": "active_ingredient_reference",
                        "review_status": "public_label_verified",
                        "reviewed_by": SEED_ID,
                        "reviewed_at": func.now(),
                        "is_current": True,
                        "updated_at": func.now(),
                    },
                )
            )
            await session.execute(stmt)
            links += 1

    if missing:
        raise RuntimeError(
            "No safe canonical product link found for structured leaflet groups: "
            + ", ".join(missing)
        )

    await session.flush()
    return SeedSummary(
        documents_fetched=fetched,
        structured_documents=structured,
        medication_links=links,
        products_without_safe_reference=tuple(missing),
    )


async def async_main(args: argparse.Namespace) -> int:
    database_url = args.database_url or os.getenv("DATABASE_URL")
    if not database_url:
        raise RuntimeError("DATABASE_URL is required")
    if not database_url.startswith("postgresql+asyncpg://"):
        raise RuntimeError("DATABASE_URL must use the postgresql+asyncpg driver")

    engine = create_async_engine(database_url, pool_pre_ping=True)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    timeout = httpx.Timeout(45.0, connect=15.0)
    try:
        async with httpx.AsyncClient(
            timeout=timeout,
            follow_redirects=True,
            headers={"User-Agent": "NursingClinicalRelease/1.5.1"},
        ) as client:
            async with session_factory() as session:
                async with session.begin():
                    summary = await seed_structured_leaflets(
                        session,
                        client=client,
                    )
        print(json.dumps(asdict(summary), ensure_ascii=False, indent=2))
        return 0
    finally:
        await engine.dispose()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Fetch five public DailyMed SPL documents, structure clinical "
            "sections and link them to canonical single-ingredient products."
        )
    )
    parser.add_argument("--database-url", default=None, help="Overrides DATABASE_URL.")
    return parser


def main() -> int:
    return asyncio.run(async_main(build_parser().parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
