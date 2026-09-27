from __future__ import annotations

import os
import uuid
from datetime import datetime, timezone

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.db.models import (
    ActiveIngredient,
    FieldProvenance,
    MedicationProduct,
    Presentation,
    SourceAssertion,
    SourceSnapshot,
    SourceSystem,
)
from scripts.entity_resolution import normalize_name, resolve_entities, split_active_ingredients


def test_name_normalization_and_conservative_ingredient_split() -> None:
    assert normalize_name("  Ácido   Ascórbico ") == "acido ascorbico"
    assert split_active_ingredients("Dipirona + Cafeína; Paracetamol") == [
        "Dipirona",
        "Cafeína",
        "Paracetamol",
    ]


@pytest.mark.asyncio
async def test_entity_resolution_promotes_anvisa_data_and_keeps_calculation_closed() -> None:
    database_url = os.environ["DATABASE_URL"]
    engine = create_async_engine(database_url)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    suffix = uuid.uuid4().hex[:10]
    registration = f"TEST-{suffix}"
    snapshot_id = uuid.uuid4()

    try:
        async with session_factory() as session:
            transaction = await session.begin()
            try:
                source = await session.scalar(
                    select(SourceSystem).where(SourceSystem.code == "ANVISA")
                )
                if source is None:
                    source = SourceSystem(
                        id=uuid.uuid4(),
                        code="ANVISA",
                        name="Agência Nacional de Vigilância Sanitária",
                        country_code="BR",
                        authority_level=100,
                        is_active=True,
                    )
                    session.add(source)
                    await session.flush()

                snapshot = SourceSnapshot(
                    id=snapshot_id,
                    source_system_id=source.id,
                    dataset_name="DADOS_ABERTOS_MEDICAMENTOS.csv",
                    source_version=f"test-{suffix}",
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
                    external_record_id=f"reg:{registration}",
                    entity_type="anvisa_medication_record",
                    entity_key={"registration_number": registration},
                    attribute_name="record",
                    value_text="Produto Teste — Dipirona + Cafeína",
                    value_json={
                        "raw": {},
                        "normalized": {
                            "NUMERO_REGISTRO_PRODUTO": registration,
                            "NOME_PRODUTO": "Produto Teste",
                            "PRINCIPIO_ATIVO": "Dipirona + Cafeína",
                            "EMPRESA_DETENTORA_REGISTRO": "Fabricante Teste S.A.",
                            "SITUACAO_REGISTRO": "VÁLIDO",
                            "APRESENTACAO": "500 mg/mL - ampola 2 mL",
                            "FORMA_FARMACEUTICA": "Solução injetável",
                            "CONCENTRACAO": "500 mg/mL",
                        },
                    },
                    language_code="pt-BR",
                    content_hash=(suffix * 7)[:64].ljust(64, "1"),
                )
                session.add(assertion)
                await session.flush()

                summary = await resolve_entities(session, snapshot_id=snapshot.id)

                assert summary.assertions_read == 1
                assert summary.medication_products == 1
                assert summary.active_ingredients == 2
                assert summary.presentations == 1
                assert summary.presentations_skipped == 0

                product = await session.scalar(
                    select(MedicationProduct).where(
                        MedicationProduct.anvisa_registration_number == registration
                    )
                )
                assert product is not None
                assert product.brand_name == "Produto Teste"
                assert product.generic_name == "Dipirona + Cafeína"
                assert product.manufacturer_name == "Fabricante Teste S.A."

                ingredient_names = set(
                    (
                        await session.scalars(
                            select(ActiveIngredient.canonical_name).where(
                                ActiveIngredient.normalized_name.in_(
                                    ["dipirona", "cafeina"]
                                )
                            )
                        )
                    ).all()
                )
                assert ingredient_names == {"Dipirona", "Cafeína"}

                presentation = await session.scalar(
                    select(Presentation).where(
                        Presentation.medication_product_id == product.id
                    )
                )
                assert presentation is not None
                assert presentation.calculation_ready is False
                assert presentation.concentration_value is None
                assert presentation.concentration_unit is None
                assert presentation.concentration_denominator_value is None
                assert presentation.concentration_denominator_unit is None
                assert presentation.strength_text == "500 mg/mL"

                provenance_count = await session.scalar(
                    select(func.count(FieldProvenance.id)).where(
                        FieldProvenance.source_assertion_id == assertion.id
                    )
                )
                assert provenance_count is not None
                assert provenance_count >= 10
            finally:
                await transaction.rollback()
    finally:
        await engine.dispose()
