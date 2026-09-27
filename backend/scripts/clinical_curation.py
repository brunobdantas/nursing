from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import uuid
from dataclasses import asdict, dataclass
from decimal import Decimal, InvalidOperation
from typing import Any

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.db.models import FieldProvenance, Presentation


PARSER_ID = "CONCENTRATION_REGEX_V1"
PARSER_VERSION = "1.0.0"

# Deliberately narrow for the MVP calculator contract:
#   mass: mg or g (g is normalized deterministically to mg)
#   volume: mL
#   denominator value may be omitted only for the canonical "mg/mL" shape.
_CONCENTRATION_RE = re.compile(
    r"(?<![\w])"
    r"(?P<numerator>\d+(?:[\.,]\d+)?)\s*"
    r"(?P<numerator_unit>mg|g)\s*/\s*"
    r"(?:(?P<denominator>\d+(?:[\.,]\d+)?)\s*)?"
    r"(?P<denominator_unit>mL)"
    r"(?![\w])",
    re.IGNORECASE,
)

_MASS_UNIT_RE = re.compile(r"(?<![\w])(?:mg|g)(?![\w])", re.IGNORECASE)


@dataclass(frozen=True)
class ParsedConcentration:
    numerator_value: Decimal
    numerator_unit: str
    denominator_value: Decimal
    denominator_unit: str
    source_text: str


@dataclass(frozen=True)
class CurationSummary:
    presentations_scanned: int
    presentations_curated: int
    presentations_skipped: int


def _decimal(value: str) -> Decimal:
    return Decimal(value.replace(",", "."))


def parse_concentration(text: str | None) -> ParsedConcentration | None:
    """
    Parse only unambiguous mass-per-volume concentrations.

    Safety properties:
    - exactly one supported concentration expression must exist;
    - combination expressions containing '+' are rejected;
    - exactly one mass unit token must exist in the text;
    - numerator/denominator must be finite and strictly positive;
    - denominator unit is mL only;
    - grams are normalized exactly to milligrams.
    """
    if text is None:
        return None

    normalized_text = " ".join(text.split())
    if not normalized_text:
        return None

    # Combination products such as "500 mg + 125 mg / 5 mL" must never be
    # reduced to one component by an automated parser.
    if "+" in normalized_text:
        return None

    matches = list(_CONCENTRATION_RE.finditer(normalized_text))
    if len(matches) != 1:
        return None

    # If another mass amount exists outside the matched concentration, the text
    # is clinically ambiguous for this narrow parser.
    if len(_MASS_UNIT_RE.findall(normalized_text)) != 1:
        return None

    match = matches[0]
    try:
        numerator = _decimal(match.group("numerator"))
        denominator_raw = match.group("denominator")
        denominator = _decimal(denominator_raw) if denominator_raw else Decimal("1")
    except (InvalidOperation, ValueError):
        return None

    if not numerator.is_finite() or not denominator.is_finite():
        return None
    if numerator <= 0 or denominator <= 0:
        return None

    numerator_unit = match.group("numerator_unit").casefold()
    if numerator_unit == "g":
        numerator *= Decimal("1000")
    elif numerator_unit != "mg":
        return None

    return ParsedConcentration(
        numerator_value=numerator,
        numerator_unit="mg",
        denominator_value=denominator,
        denominator_unit="mL",
        source_text=normalized_text,
    )


def _equivalent(
    first: ParsedConcentration,
    second: ParsedConcentration,
) -> bool:
    # Compare normalized concentration ratios without floating point.
    return (
        first.numerator_unit == second.numerator_unit
        and first.denominator_unit == second.denominator_unit
        and first.numerator_value * second.denominator_value
        == second.numerator_value * first.denominator_value
    )


def choose_concentration_source(
    presentation: Presentation,
) -> tuple[str, ParsedConcentration] | None:
    strength = parse_concentration(presentation.strength_text)
    description = parse_concentration(presentation.description)

    if strength is not None and description is not None:
        if not _equivalent(strength, description):
            return None
        return "strength_text", strength

    if strength is not None:
        return "strength_text", strength

    if description is not None:
        return "description", description

    return None


async def _source_assertion_id(
    session: AsyncSession,
    *,
    presentation_id: uuid.UUID,
    source_field_name: str,
) -> uuid.UUID | None:
    """
    Automated curation is allowed only when the parsed source field is already
    traceable to a STAGING assertion.
    """
    return await session.scalar(
        select(FieldProvenance.source_assertion_id)
        .where(
            FieldProvenance.target_layer == "canonical",
            FieldProvenance.target_entity_type == "presentation",
            FieldProvenance.target_entity_id == presentation_id,
            FieldProvenance.target_field_name == source_field_name,
        )
        .order_by(
            FieldProvenance.is_primary.desc(),
            FieldProvenance.created_at.desc(),
        )
        .limit(1)
    )


async def _record_parser_provenance(
    session: AsyncSession,
    *,
    source_assertion_id: uuid.UUID,
    presentation_id: uuid.UUID,
    target_field_name: str,
    source_text: str,
) -> None:
    note = (
        f"{PARSER_ID}@{PARSER_VERSION}; exact supported concentration pattern; "
        f"source_text={source_text!r}"
    )
    stmt = (
        pg_insert(FieldProvenance)
        .values(
            id=uuid.uuid4(),
            source_assertion_id=source_assertion_id,
            target_layer="canonical",
            target_entity_type="presentation",
            target_entity_id=presentation_id,
            target_field_name=target_field_name,
            is_primary=True,
            confidence=Decimal("1"),
            review_status="automated_validated",
            reviewed_by=PARSER_ID,
            note=note,
        )
        .on_conflict_do_update(
            index_elements=[
                FieldProvenance.target_layer,
                FieldProvenance.target_entity_type,
                FieldProvenance.target_entity_id,
                FieldProvenance.target_field_name,
                FieldProvenance.source_assertion_id,
            ],
            set_={
                "is_primary": True,
                "confidence": Decimal("1"),
                "review_status": "automated_validated",
                "reviewed_by": PARSER_ID,
                "note": note,
            },
        )
    )
    await session.execute(stmt)


async def curate_presentations(session: AsyncSession) -> CurationSummary:
    presentations = list(
        (
            await session.scalars(
                select(Presentation)
                .where(
                    Presentation.is_active.is_(True),
                    Presentation.calculation_ready.is_(False),
                )
                .order_by(Presentation.id)
            )
        ).all()
    )

    curated = 0
    skipped = 0

    for presentation in presentations:
        # Fail closed on partially populated legacy/drifted structures.
        structured_values: tuple[Any, ...] = (
            presentation.concentration_value,
            presentation.concentration_unit,
            presentation.concentration_denominator_value,
            presentation.concentration_denominator_unit,
        )
        if any(value is not None for value in structured_values):
            skipped += 1
            continue

        chosen = choose_concentration_source(presentation)
        if chosen is None:
            skipped += 1
            continue

        source_field_name, parsed = chosen
        assertion_id = await _source_assertion_id(
            session,
            presentation_id=presentation.id,
            source_field_name=source_field_name,
        )
        if assertion_id is None:
            # No provenance means no automatic calculator enablement.
            skipped += 1
            continue

        presentation.concentration_value = parsed.numerator_value
        presentation.concentration_unit = parsed.numerator_unit
        presentation.concentration_denominator_value = parsed.denominator_value
        presentation.concentration_denominator_unit = parsed.denominator_unit
        presentation.calculation_ready = True

        for field_name in (
            "concentration_value",
            "concentration_unit",
            "concentration_denominator_value",
            "concentration_denominator_unit",
            "calculation_ready",
        ):
            await _record_parser_provenance(
                session,
                source_assertion_id=assertion_id,
                presentation_id=presentation.id,
                target_field_name=field_name,
                source_text=parsed.source_text,
            )

        curated += 1

    await session.flush()
    return CurationSummary(
        presentations_scanned=len(presentations),
        presentations_curated=curated,
        presentations_skipped=skipped,
    )


async def async_main(args: argparse.Namespace) -> int:
    database_url = args.database_url or os.getenv("DATABASE_URL")
    if not database_url:
        raise RuntimeError("DATABASE_URL is required")
    if not database_url.startswith("postgresql+asyncpg://"):
        raise RuntimeError("DATABASE_URL must use the postgresql+asyncpg driver")

    engine = create_async_engine(database_url, pool_pre_ping=True)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    try:
        async with session_factory() as session:
            async with session.begin():
                summary = await curate_presentations(session)

        print(json.dumps(asdict(summary), ensure_ascii=False, indent=2))
        return 0
    finally:
        await engine.dispose()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Conservatively structure ANVISA presentation concentrations and "
            "enable calculator-ready rows only when traceable and unambiguous."
        )
    )
    parser.add_argument("--database-url", default=None, help="Overrides DATABASE_URL.")
    return parser


def main() -> int:
    return asyncio.run(async_main(build_parser().parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
