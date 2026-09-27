from __future__ import annotations

import io
import os
import uuid
from decimal import Decimal

import pytest
from openpyxl import Workbook
from sqlalchemy import select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.db.models import MedicationProduct, Presentation
from scripts.clinical_curation import curate_presentations
from scripts.cmed_enrichment import (
    _latest_xlsx_url,
    enrich_cmed,
    infer_dosage_form,
    infer_route,
    load_cmed_dataframe,
    normalize_registration,
)
from scripts.entity_resolution import is_regulatory_active


def _workbook_bytes() -> bytes:
    workbook = Workbook()
    sheet = workbook.active
    sheet.append(["Lista oficial CMED"])
    sheet.append(
        [
            "REGISTRO",
            "PRODUTO",
            "APRESENTAÇÃO",
            "CÓDIGO GGREM",
            "EAN 1",
            "CLASSE TERAPÊUTICA",
            "TIPO DE PRODUTO (STATUS DO PRODUTO)",
        ]
    )
    sheet.append(
        [
            "101160143",
            "CEFACLOR",
            "250 MG / 5 ML PO P/ SUS OR FR VD AMB X 100 ML",
            "1234567890123",
            "7890000000001",
            "ANTIBACTERIANOS SISTÊMICOS",
            "Genérico",
        ]
    )
    output = io.BytesIO()
    workbook.save(output)
    return output.getvalue()


def test_cmed_portal_download_link_accepts_download_suffix() -> None:
    page = (
        '<a href="./arquivos/xls_conformidade_site_20260909_222937320.xlsx/'
        '@@download/file">PMC - xls</a>'
    )

    assert _latest_xlsx_url(page).endswith(
        "xls_conformidade_site_20260909_222937320.xlsx/@@download/file"
    )


def test_cmed_workbook_header_detection_and_normalization() -> None:
    frame = load_cmed_dataframe(_workbook_bytes())

    assert "REGISTRO" in frame.columns
    assert "APRESENTACAO" in frame.columns
    assert frame.iloc[0]["PRODUTO"] == "CEFACLOR"
    assert normalize_registration("1.0116.0143") == "101160143"


def test_cmed_inference_is_conservative() -> None:
    text = "250 MG / 5 ML PO P/ SUS OR FR VD AMB X 100 ML"

    assert infer_dosage_form(text) == "Pó para suspensão oral"
    assert infer_route(text) == ("ORAL", "Oral")
    assert infer_route("500 MG COM CT BL AL PLAS X 20") is None


@pytest.mark.parametrize(
    ("status", "expected"),
    [
        ("VÁLIDO", True),
        ("Ativo", True),
        ("Vigente", True),
        ("Inativo", False),
        ("Cancelado", False),
        ("Caduco", False),
        (None, False),
    ],
)
def test_regulatory_status_gate(status: str | None, expected: bool) -> None:
    assert is_regulatory_active(status) is expected


@pytest.mark.asyncio
async def test_cmed_creates_presentation_then_curation_enables_safe_calculation() -> None:
    engine = create_async_engine(os.environ["DATABASE_URL"])
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    try:
        async with session_factory() as session:
            transaction = await session.begin()
            try:
                product = MedicationProduct(
                    id=uuid.uuid4(),
                    brand_name="CEFACLOR",
                    normalized_brand_name="cefaclor",
                    generic_name="CEFACLOR",
                    normalized_generic_name="cefaclor",
                    anvisa_registration_number="101160143",
                    manufacturer_name="Fabricante teste",
                    regulatory_status="VÁLIDO",
                    country_code="BR",
                    is_active=True,
                )
                session.add(product)
                await session.flush()

                summary = await enrich_cmed(
                    session,
                    source_url="https://www.gov.br/anvisa/cmed/teste.xlsx",
                    content=_workbook_bytes(),
                    response_headers={},
                )

                assert summary.rows_matched == 1
                assert summary.presentations_upserted == 1
                await session.refresh(product)
                assert product.therapeutic_class == "ANTIBACTERIANOS SISTÊMICOS"
                assert product.product_type == "Genérico"

                presentation = await session.scalar(
                    select(Presentation).where(
                        Presentation.medication_product_id == product.id
                    )
                )
                assert presentation is not None
                assert presentation.description.startswith("250 MG / 5 ML")
                assert presentation.calculation_ready is False

                curation = await curate_presentations(session)
                assert curation.presentations_curated == 1

                await session.refresh(presentation)
                assert presentation.calculation_ready is True
                assert presentation.concentration_value == Decimal("250")
                assert presentation.concentration_unit == "mg"
                assert presentation.concentration_denominator_value == Decimal("5")
                assert presentation.concentration_denominator_unit == "mL"
            finally:
                await transaction.rollback()
    finally:
        await engine.dispose()


@pytest.mark.asyncio
async def test_cmed_does_not_publish_inactive_regulatory_product() -> None:
    engine = create_async_engine(os.environ["DATABASE_URL"])
    session_factory = async_sessionmaker(engine, expire_on_commit=False)

    try:
        async with session_factory() as session:
            transaction = await session.begin()
            try:
                product = MedicationProduct(
                    id=uuid.uuid4(),
                    brand_name="CEFACLOR",
                    normalized_brand_name="cefaclor",
                    generic_name="CEFACLOR",
                    normalized_generic_name="cefaclor",
                    anvisa_registration_number="101160143",
                    manufacturer_name="Fabricante teste",
                    regulatory_status="Inativo",
                    country_code="BR",
                    is_active=False,
                )
                session.add(product)
                await session.flush()

                summary = await enrich_cmed(
                    session,
                    source_url="https://www.gov.br/anvisa/cmed/teste.xlsx",
                    content=_workbook_bytes(),
                    response_headers={},
                )

                assert summary.rows_matched == 0
                assert summary.presentations_upserted == 0
            finally:
                await transaction.rollback()
    finally:
        await engine.dispose()
