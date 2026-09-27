from __future__ import annotations

import os
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.db.models import (
    DosageForm,
    FieldProvenance,
    MedicationProduct,
    Presentation,
    SourceAssertion,
    SourceSnapshot,
    SourceSystem,
)
from scripts.clinical_curation import (
    PARSER_ID,
    curate_presentations,
    parse_concentration,
)


@pytest.mark.parametrize(
    ("text", "numerator", "denominator"),
    [
        ("500 mg/mL", Decimal("500"), Decimal("1")),
        ("1 g/2 mL", Decimal("1000"), Decimal("2")),
        ("250 mg / 5 mL", Decimal("250"), Decimal("5")),
        ("Concentração 500 mg/mL", Decimal("500"), Decimal("1")),
    ],
)
def test_parse_concentration_accepts_only_supported_exact_units(
    text: str,
    numerator: Decimal,
    denominator: Decimal,
) -> None:
    parsed = parse_concentration(text)

    assert parsed is not None
    assert parsed.numerator_value == numerator
    assert parsed.numerator_unit == "mg"
    assert parsed.denominator_value == denominator
    assert parsed.denominator_unit == "mL"


@pytest.mark.parametrize(
    "text",
    [
        None,
        "",
        "500 mg + 125 mg / 5 mL",
        "500 mg/5 mL + 10 mg",
        "10 mg/mL e 20 mg/mL",
        "5%",
        "500 mg/L",
        "0 mg/mL",
        "500 mg/0 mL",
    ],
)
def test_parse_concentration_rejects_ambiguous_or_unsupported_text(
    text: str | None,
) -> None:
    assert parse_concentration(text) is None


@pytest.mark.asyncio
async def test_curation_structures_traceable_presentation_and_enables_calculation() -> None:
    engine = create_async_engine(os.environ["DATABASE_URL"])
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    suffix = uuid.uuid4().hex[:10]

    try:
        async with session_factory() as session:
            transaction = await session.begin()
            try:
                source = SourceSystem(
                    id=uuid.uuid4(),
                    code=f"CURATION_{suffix}",
                    name="Clinical Curation Test Source",
                    country_code="BR",
                    authority_level=100,
                    is_active=True,
                )
                session.add(source)
                await session.flush()

                snapshot = SourceSnapshot(
                    id=uuid.uuid4(),
                    source_system_id=source.id,
                    dataset_name="curation-test.csv",
                    source_version=suffix,
                    retrieved_at=datetime.now(timezone.utc),
                    checksum_sha256=(suffix * 7)[:64].ljust(64, "0"),
                    raw_object_uri=f"file:///tmp/{suffix}.csv",
                    etl_version="test",
                    schema_version="test",
                    snapshot_metadata={"row_count": 1},
                )
                session.add(snapshot)
                await session.flush()

                assertion = SourceAssertion(
                    id=uuid.uuid4(),
                    source_snapshot_id=snapshot.id,
                    external_record_id=f"test:{suffix}",
                    entity_type="anvisa_medication_record",
                    entity_key={"registration_number": suffix},
                    attribute_name="record",
                    value_text="1 g/2 mL",
                    value_json={"normalized": {"CONCENTRACAO": "1 g/2 mL"}},
                    language_code="pt-BR",
                    content_hash=(suffix * 7)[:64].ljust(64, "1"),
                )
                session.add(assertion)

                dosage_form = DosageForm(
                    id=uuid.uuid4(),
                    code=f"INJ_{suffix}",
                    name=f"Solução injetável {suffix}",
                    normalized_name=f"solucao injetavel {suffix}",
                    is_active=True,
                )
                product = MedicationProduct(
                    id=uuid.uuid4(),
                    brand_name=f"Produto {suffix}",
                    normalized_brand_name=f"produto {suffix}",
                    generic_name="substância teste",
                    normalized_generic_name="substancia teste",
                    anvisa_registration_number=f"REG-{suffix}",
                    manufacturer_name="Fabricante Teste",
                    regulatory_status="VÁLIDO",
                    country_code="BR",
                    is_active=True,
                )
                session.add_all([dosage_form, product])
                await session.flush()

                presentation = Presentation(
                    id=uuid.uuid4(),
                    medication_product_id=product.id,
                    dosage_form_id=dosage_form.id,
                    external_presentation_code=f"PRE-{suffix}",
                    description="Ampola 2 mL",
                    strength_text="1 g/2 mL",
                    calculation_ready=False,
                    regulatory_status="VÁLIDO",
                    is_active=True,
                )
                session.add(presentation)
                await session.flush()

                source_link = FieldProvenance(
                    id=uuid.uuid4(),
                    source_assertion_id=assertion.id,
                    target_layer="canonical",
                    target_entity_type="presentation",
                    target_entity_id=presentation.id,
                    target_field_name="strength_text",
                    is_primary=True,
                    confidence=Decimal("1"),
                    review_status="pending",
                )
                session.add(source_link)
                await session.flush()

                summary = await curate_presentations(session)

                assert summary.presentations_curated == 1
                await session.refresh(presentation)
                assert presentation.calculation_ready is True
                assert presentation.concentration_value == Decimal("1000")
                assert presentation.concentration_unit == "mg"
                assert presentation.concentration_denominator_value == Decimal("2")
                assert presentation.concentration_denominator_unit == "mL"

                parser_links = list(
                    (
                        await session.scalars(
                            select(FieldProvenance).where(
                                FieldProvenance.target_entity_id == presentation.id,
                                FieldProvenance.reviewed_by == PARSER_ID,
                            )
                        )
                    ).all()
                )
                assert len(parser_links) == 5
                assert {link.target_field_name for link in parser_links} == {
                    "concentration_value",
                    "concentration_unit",
                    "concentration_denominator_value",
                    "concentration_denominator_unit",
                    "calculation_ready",
                }
                assert all(
                    link.review_status == "automated_validated"
                    and link.confidence == Decimal("1")
                    for link in parser_links
                )
            finally:
                await transaction.rollback()
    finally:
        await engine.dispose()


@pytest.mark.asyncio
async def test_curation_fails_closed_without_source_provenance() -> None:
    engine = create_async_engine(os.environ["DATABASE_URL"])
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    suffix = uuid.uuid4().hex[:10]

    try:
        async with session_factory() as session:
            transaction = await session.begin()
            try:
                dosage_form = DosageForm(
                    id=uuid.uuid4(),
                    code=f"ORAL_{suffix}",
                    name=f"Solução oral {suffix}",
                    normalized_name=f"solucao oral {suffix}",
                    is_active=True,
                )
                product = MedicationProduct(
                    id=uuid.uuid4(),
                    brand_name=None,
                    normalized_brand_name=None,
                    generic_name=f"produto sem proveniência {suffix}",
                    normalized_generic_name=f"produto sem proveniencia {suffix}",
                    anvisa_registration_number=f"NOPROV-{suffix}",
                    manufacturer_name=None,
                    regulatory_status="VÁLIDO",
                    country_code="BR",
                    is_active=True,
                )
                session.add_all([dosage_form, product])
                await session.flush()

                presentation = Presentation(
                    id=uuid.uuid4(),
                    medication_product_id=product.id,
                    dosage_form_id=dosage_form.id,
                    external_presentation_code=f"NOPROV-PRE-{suffix}",
                    description="250 mg / 5 mL",
                    strength_text="250 mg / 5 mL",
                    calculation_ready=False,
                    is_active=True,
                )
                session.add(presentation)
                await session.flush()

                await curate_presentations(session)
                await session.refresh(presentation)

                assert presentation.calculation_ready is False
                assert presentation.concentration_value is None
                assert (
                    await session.scalar(
                        select(func.count(FieldProvenance.id)).where(
                            FieldProvenance.target_entity_id == presentation.id,
                            FieldProvenance.reviewed_by == PARSER_ID,
                        )
                    )
                    == 0
                )
            finally:
                await transaction.rollback()
    finally:
        await engine.dispose()
