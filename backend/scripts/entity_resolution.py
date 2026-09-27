from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import os
import re
import unicodedata
import uuid
from dataclasses import asdict, dataclass
from typing import Any

from sqlalchemy import Select, func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.db.models import (
    ActiveIngredient,
    DosageForm,
    FieldProvenance,
    MedicationProduct,
    MedicationProductIngredient,
    Presentation,
    SourceAssertion,
    SourceSnapshot,
    SourceSystem,
)


@dataclass(frozen=True)
class ResolutionSummary:
    snapshot_id: uuid.UUID
    assertions_read: int
    active_ingredients: int
    medication_products: int
    presentations: int
    presentations_skipped: int


def normalize_name(value: str) -> str:
    """Accent-insensitive, whitespace-stable canonical lookup key."""
    text = unicodedata.normalize("NFKD", value)
    text = "".join(char for char in text if not unicodedata.combining(char))
    text = re.sub(r"\s+", " ", text).strip().casefold()
    return text


def _clean(value: Any) -> str | None:
    if value is None:
        return None
    text = re.sub(r"\s+", " ", str(value)).strip()
    return text or None


def _first(row: dict[str, Any], *keys: str) -> str | None:
    for key in keys:
        value = _clean(row.get(key))
        if value:
            return value
    return None


def _normalized_payload(assertion: SourceAssertion) -> dict[str, Any] | None:
    payload = assertion.value_json
    if not isinstance(payload, dict):
        return None
    normalized = payload.get("normalized")
    return normalized if isinstance(normalized, dict) else None


def split_active_ingredients(value: str) -> list[str]:
    """
    Conservative split of explicitly separated active ingredients.

    We intentionally do not split on slashes, commas or hyphens because those
    characters frequently belong to legitimate substance names/concentrations.
    """
    parts = re.split(r"\s+\+\s+|\s*;\s*|[\r\n]+", value)
    result: list[str] = []
    seen: set[str] = set()
    for part in parts:
        cleaned = _clean(part)
        if not cleaned:
            continue
        key = normalize_name(cleaned)
        if key and key not in seen:
            seen.add(key)
            result.append(cleaned)
    return result


def is_regulatory_active(status: str | None) -> bool:
    """Map ANVISA registration status to the app's active-content gate."""
    if not status:
        return False
    normalized = normalize_name(status)
    blocked = ("inativ", "cancel", "caduc", "suspens", "vencid")
    if any(token in normalized for token in blocked):
        return False
    return any(
        token in normalized
        for token in ("valido", "ativo", "vigente", "regular")
    )


def _dosage_form_code(normalized_name: str) -> str:
    digest = hashlib.sha256(normalized_name.encode("utf-8")).hexdigest()[:12].upper()
    return f"ANVISA_{digest}"


def _presentation_code(
    registration: str,
    presentation_description: str,
    dosage_form_name: str,
) -> str:
    material = "|".join(
        (
            registration,
            normalize_name(presentation_description),
            normalize_name(dosage_form_name),
        )
    )
    digest = hashlib.sha256(material.encode("utf-8")).hexdigest()[:24]
    return f"ANVISA-{digest}"


async def _resolve_snapshot_id(
    session: AsyncSession,
    requested_snapshot_id: uuid.UUID | None,
) -> uuid.UUID:
    if requested_snapshot_id is not None:
        exists = await session.scalar(
            select(SourceSnapshot.id)
            .join(SourceSystem, SourceSystem.id == SourceSnapshot.source_system_id)
            .where(
                SourceSnapshot.id == requested_snapshot_id,
                SourceSystem.code == "ANVISA",
            )
        )
        if exists is None:
            raise RuntimeError("Requested snapshot is not an ANVISA snapshot")
        return exists

    snapshot_id = await session.scalar(
        select(SourceSnapshot.id)
        .join(SourceSystem, SourceSystem.id == SourceSnapshot.source_system_id)
        .where(SourceSystem.code == "ANVISA")
        .order_by(SourceSnapshot.retrieved_at.desc())
        .limit(1)
    )
    if snapshot_id is None:
        raise RuntimeError("No ANVISA source snapshot is available in RAW")
    return snapshot_id


async def _upsert_active_ingredient(
    session: AsyncSession,
    canonical_name: str,
) -> uuid.UUID:
    normalized = normalize_name(canonical_name)
    stmt = (
        pg_insert(ActiveIngredient)
        .values(
            id=uuid.uuid4(),
            canonical_name=canonical_name,
            normalized_name=normalized,
            is_active=True,
        )
        .on_conflict_do_update(
            index_elements=[ActiveIngredient.normalized_name],
            set_={
                "canonical_name": canonical_name,
                "is_active": True,
                "updated_at": func.now(),
            },
        )
        .returning(ActiveIngredient.id)
    )
    return (await session.execute(stmt)).scalar_one()


async def _upsert_product(
    session: AsyncSession,
    *,
    registration: str,
    brand_name: str | None,
    generic_name: str,
    manufacturer_name: str | None,
    regulatory_status: str | None,
    is_active: bool,
) -> uuid.UUID:
    stmt = (
        pg_insert(MedicationProduct)
        .values(
            id=uuid.uuid4(),
            brand_name=brand_name,
            normalized_brand_name=normalize_name(brand_name) if brand_name else None,
            generic_name=generic_name,
            normalized_generic_name=normalize_name(generic_name),
            anvisa_registration_number=registration,
            manufacturer_name=manufacturer_name,
            regulatory_status=regulatory_status,
            country_code="BR",
            is_active=is_active,
        )
        .on_conflict_do_update(
            index_elements=[MedicationProduct.anvisa_registration_number],
            set_={
                "brand_name": brand_name,
                "normalized_brand_name": normalize_name(brand_name) if brand_name else None,
                "generic_name": generic_name,
                "normalized_generic_name": normalize_name(generic_name),
                "manufacturer_name": manufacturer_name,
                "regulatory_status": regulatory_status,
                "country_code": "BR",
                "is_active": is_active,
                "updated_at": func.now(),
            },
        )
        .returning(MedicationProduct.id)
    )
    return (await session.execute(stmt)).scalar_one()


async def _link_product_ingredient(
    session: AsyncSession,
    *,
    product_id: uuid.UUID,
    ingredient_id: uuid.UUID,
    sequence_order: int,
) -> None:
    stmt = (
        pg_insert(MedicationProductIngredient)
        .values(
            medication_product_id=product_id,
            active_ingredient_id=ingredient_id,
            sequence_order=sequence_order,
            ingredient_role="active",
        )
        .on_conflict_do_update(
            index_elements=[
                MedicationProductIngredient.medication_product_id,
                MedicationProductIngredient.active_ingredient_id,
            ],
            set_={
                "sequence_order": sequence_order,
                "ingredient_role": "active",
                "updated_at": func.now(),
            },
        )
    )
    await session.execute(stmt)


async def _upsert_dosage_form(
    session: AsyncSession,
    dosage_form_name: str,
) -> uuid.UUID:
    normalized = normalize_name(dosage_form_name)
    stmt = (
        pg_insert(DosageForm)
        .values(
            id=uuid.uuid4(),
            code=_dosage_form_code(normalized),
            name=dosage_form_name,
            normalized_name=normalized,
            is_active=True,
        )
        .on_conflict_do_update(
            index_elements=[DosageForm.normalized_name],
            set_={
                "name": dosage_form_name,
                "is_active": True,
                "updated_at": func.now(),
            },
        )
        .returning(DosageForm.id)
    )
    return (await session.execute(stmt)).scalar_one()


async def _upsert_presentation(
    session: AsyncSession,
    *,
    product_id: uuid.UUID,
    dosage_form_id: uuid.UUID,
    external_code: str,
    description: str,
    strength_text: str | None,
    regulatory_status: str | None,
) -> uuid.UUID:
    """
    Automated source resolution is NEVER authorized to enable calculations.

    On INSERT calculation_ready is explicitly False. On UPDATE the column is
    deliberately omitted so a presentation that was later clinically reviewed
    is not silently downgraded by a source refresh.
    """
    stmt = (
        pg_insert(Presentation)
        .values(
            id=uuid.uuid4(),
            medication_product_id=product_id,
            dosage_form_id=dosage_form_id,
            external_presentation_code=external_code,
            description=description,
            strength_text=strength_text,
            concentration_value=None,
            concentration_unit=None,
            concentration_denominator_value=None,
            concentration_denominator_unit=None,
            package_quantity=None,
            package_unit=None,
            calculation_ready=False,
            regulatory_status=regulatory_status,
            is_active=True,
        )
        .on_conflict_do_update(
            index_elements=[
                Presentation.medication_product_id,
                Presentation.external_presentation_code,
            ],
            set_={
                "dosage_form_id": dosage_form_id,
                "description": description,
                "strength_text": strength_text,
                "regulatory_status": regulatory_status,
                "is_active": True,
                "updated_at": func.now(),
            },
        )
        .returning(Presentation.id)
    )
    return (await session.execute(stmt)).scalar_one()


async def _record_provenance(
    session: AsyncSession,
    *,
    assertion_id: uuid.UUID,
    target_entity_type: str,
    target_entity_id: uuid.UUID,
    target_field_name: str,
) -> None:
    stmt = (
        pg_insert(FieldProvenance)
        .values(
            id=uuid.uuid4(),
            source_assertion_id=assertion_id,
            target_layer="canonical",
            target_entity_type=target_entity_type,
            target_entity_id=target_entity_id,
            target_field_name=target_field_name,
            is_primary=True,
            confidence=1,
            review_status="pending",
        )
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
    await session.execute(stmt)


async def resolve_entities(
    session: AsyncSession,
    *,
    snapshot_id: uuid.UUID | None = None,
) -> ResolutionSummary:
    resolved_snapshot_id = await _resolve_snapshot_id(session, snapshot_id)

    stmt: Select[tuple[SourceAssertion]] = (
        select(SourceAssertion)
        .where(
            SourceAssertion.source_snapshot_id == resolved_snapshot_id,
            SourceAssertion.entity_type == "anvisa_medication_record",
            SourceAssertion.attribute_name == "record",
        )
        .order_by(SourceAssertion.external_record_id)
    )
    assertions = list((await session.scalars(stmt)).all())

    ingredient_ids: set[uuid.UUID] = set()
    product_ids: set[uuid.UUID] = set()
    presentation_ids: set[uuid.UUID] = set()
    presentations_skipped = 0

    for assertion in assertions:
        row = _normalized_payload(assertion)
        if row is None:
            continue

        registration = _first(row, "NUMERO_REGISTRO_PRODUTO", "REGISTRO")
        product_name = _first(row, "NOME_PRODUTO", "PRODUTO", "NOME_COMERCIAL")
        active_ingredient_text = _first(row, "PRINCIPIO_ATIVO")
        manufacturer = _first(
            row,
            "EMPRESA_DETENTORA_REGISTRO",
            "DETENTOR_REGISTRO",
            "EMPRESA",
        )
        regulatory_status = _first(
            row,
            "SITUACAO_REGISTRO",
            "SITUACAO",
            "STATUS_REGISTRO",
        )

        # A canonical medication product without a regulatory registration
        # number would not have a stable ANVISA identity, so fail-safe by skipping.
        if not registration:
            continue

        ingredient_names = (
            split_active_ingredients(active_ingredient_text)
            if active_ingredient_text
            else []
        )
        generic_name = (
            _first(row, "NOME_GENERICO", "NOME_GENERICO_PRODUTO")
            or active_ingredient_text
            or product_name
        )
        if not generic_name:
            continue

        product_id = await _upsert_product(
            session,
            registration=registration,
            brand_name=product_name,
            generic_name=generic_name,
            manufacturer_name=manufacturer,
            regulatory_status=regulatory_status,
            is_active=is_regulatory_active(regulatory_status),
        )
        product_ids.add(product_id)

        for field_name in (
            "anvisa_registration_number",
            "brand_name",
            "generic_name",
            "manufacturer_name",
            "regulatory_status",
        ):
            await _record_provenance(
                session,
                assertion_id=assertion.id,
                target_entity_type="medication_product",
                target_entity_id=product_id,
                target_field_name=field_name,
            )

        for sequence_order, ingredient_name in enumerate(ingredient_names, start=1):
            ingredient_id = await _upsert_active_ingredient(session, ingredient_name)
            ingredient_ids.add(ingredient_id)
            await _link_product_ingredient(
                session,
                product_id=product_id,
                ingredient_id=ingredient_id,
                sequence_order=sequence_order,
            )
            await _record_provenance(
                session,
                assertion_id=assertion.id,
                target_entity_type="active_ingredient",
                target_entity_id=ingredient_id,
                target_field_name="canonical_name",
            )

        presentation_description = _first(
            row,
            "APRESENTACAO",
            "DESCRICAO_APRESENTACAO",
            "DESCRICAO_DA_APRESENTACAO",
        )
        dosage_form_name = _first(
            row,
            "FORMA_FARMACEUTICA",
            "FORMA_FARMACEUTICA_PRODUTO",
        )

        # Never fabricate a presentation or dosage form. If this source record
        # does not contain both, product/ingredient promotion still succeeds.
        if not presentation_description or not dosage_form_name:
            presentations_skipped += 1
            continue

        dosage_form_id = await _upsert_dosage_form(session, dosage_form_name)
        strength_text = _first(
            row,
            "CONCENTRACAO",
            "CONCENTRACAO_APRESENTACAO",
        )
        source_presentation_code = _first(
            row,
            "CODIGO_APRESENTACAO",
            "NUMERO_APRESENTACAO",
        )
        external_code = source_presentation_code or _presentation_code(
            registration,
            presentation_description,
            dosage_form_name,
        )

        presentation_id = await _upsert_presentation(
            session,
            product_id=product_id,
            dosage_form_id=dosage_form_id,
            external_code=external_code,
            description=presentation_description,
            strength_text=strength_text,
            regulatory_status=regulatory_status,
        )
        presentation_ids.add(presentation_id)

        for field_name in (
            "description",
            "strength_text",
            "dosage_form_id",
            "regulatory_status",
        ):
            await _record_provenance(
                session,
                assertion_id=assertion.id,
                target_entity_type="presentation",
                target_entity_id=presentation_id,
                target_field_name=field_name,
            )

    await session.flush()
    return ResolutionSummary(
        snapshot_id=resolved_snapshot_id,
        assertions_read=len(assertions),
        active_ingredients=len(ingredient_ids),
        medication_products=len(product_ids),
        presentations=len(presentation_ids),
        presentations_skipped=presentations_skipped,
    )


async def async_main(args: argparse.Namespace) -> int:
    database_url = args.database_url or os.getenv("DATABASE_URL")
    if not database_url:
        raise RuntimeError("DATABASE_URL is required")
    if not database_url.startswith("postgresql+asyncpg://"):
        raise RuntimeError("DATABASE_URL must use the postgresql+asyncpg driver")

    requested_snapshot = uuid.UUID(args.snapshot_id) if args.snapshot_id else None

    engine = create_async_engine(database_url, pool_pre_ping=True)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    try:
        async with session_factory() as session:
            async with session.begin():
                summary = await resolve_entities(
                    session,
                    snapshot_id=requested_snapshot,
                )
        print(json.dumps({**asdict(summary), "snapshot_id": str(summary.snapshot_id)}, indent=2))
        return 0
    finally:
        await engine.dispose()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Promote ANVISA STAGING assertions into the CANONICAL layer."
    )
    parser.add_argument("--database-url", default=None, help="Overrides DATABASE_URL.")
    parser.add_argument(
        "--snapshot-id",
        default=None,
        help="Optional ANVISA snapshot UUID. Defaults to the latest snapshot.",
    )
    return parser


def main() -> int:
    return asyncio.run(async_main(build_parser().parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
