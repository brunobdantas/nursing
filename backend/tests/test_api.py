from __future__ import annotations

from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from app.api.router import get_db_session, router
from app.main import create_app


class FakeScalarResult:
    """Minimal SQLAlchemy ScalarResult surface used by the API routes."""

    def __init__(self, values):
        self._values = list(values)

    def all(self):
        return list(self._values)

    def unique(self):
        return self

    def one_or_none(self):
        if not self._values:
            return None
        if len(self._values) > 1:
            raise AssertionError("Test fixture returned more than one row")
        return self._values[0]


def _app_with_session(session) -> FastAPI:
    app = FastAPI()
    app.include_router(router)

    async def override_db_session():
        yield session

    app.dependency_overrides[get_db_session] = override_db_session
    return app


def _ingredient(name: str = "Dipirona"):
    return SimpleNamespace(
        id=uuid4(),
        canonical_name=name,
        normalized_name=name.casefold(),
        atc_code="N02BB02",
        is_active=True,
    )


def _presentation(*, calculation_ready: bool = True, complete_concentration: bool = True):
    dosage_form = SimpleNamespace(
        id=uuid4(),
        code="SOL_INJ",
        name="Solução injetável",
    )
    route = SimpleNamespace(id=uuid4(), code="IV", name="Intravenosa")
    route_link = SimpleNamespace(route=route)

    return SimpleNamespace(
        id=uuid4(),
        external_presentation_code="ANVISA-PRES-001",
        description="500 mg/mL - ampola 2 mL",
        strength_text="500 mg/mL",
        dosage_form=dosage_form,
        route_links=[route_link],
        concentration_value=Decimal("500") if complete_concentration else Decimal("500"),
        concentration_unit="mg" if complete_concentration else None,
        concentration_denominator_value=(
            Decimal("1") if complete_concentration else Decimal("1")
        ),
        concentration_denominator_unit="mL" if complete_concentration else None,
        package_quantity=Decimal("2"),
        package_unit="mL",
        calculation_ready=calculation_ready,
        regulatory_status="VÁLIDO",
        is_active=True,
    )


def _product(*, presentation=None, ingredient=None):
    ingredient = ingredient or _ingredient()
    presentation = presentation or _presentation()
    ingredient_link = SimpleNamespace(
        sequence_order=1,
        active_ingredient=ingredient,
    )
    return SimpleNamespace(
        id=uuid4(),
        brand_name="Novalgina",
        normalized_brand_name="novalgina",
        generic_name="Dipirona",
        normalized_generic_name="dipirona",
        anvisa_registration_number="123456789",
        manufacturer_name="Fabricante Exemplo",
        regulatory_status="VÁLIDO",
        therapeutic_class="Analgésicos",
        product_type="Referência",
        country_code="BR",
        is_active=True,
        ingredient_links=[ingredient_link],
        presentations=[presentation],
    )


@pytest.mark.asyncio
async def test_search_returns_active_ingredients_and_products_contract():
    ingredient = _ingredient()
    product = _product(ingredient=ingredient)

    session = MagicMock()
    session.scalars = AsyncMock(
        side_effect=[
            FakeScalarResult([ingredient]),
            FakeScalarResult([product]),
        ]
    )
    app = _app_with_session(session)

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.get("/v1/medications/search", params={"q": "dip"})

    assert response.status_code == 200
    payload = response.json()
    assert payload["query"] == "dip"
    assert payload["returned"] == 2

    by_type = {item["entity_type"]: item for item in payload["items"]}
    assert by_type["active_ingredient"]["display_name"] == "Dipirona"
    assert by_type["medication_product"]["display_name"] == "Novalgina"
    assert by_type["medication_product"]["secondary_name"] == "Dipirona"
    assert by_type["medication_product"]["has_calculation_ready_presentation"] is True
    assert by_type["medication_product"]["is_approximate"] is False


@pytest.mark.asyncio
async def test_medication_detail_returns_structured_concentration_contract():
    presentation = _presentation(calculation_ready=True, complete_concentration=True)
    product = _product(presentation=presentation)

    session = MagicMock()
    session.scalars = AsyncMock(return_value=FakeScalarResult([product]))
    app = _app_with_session(session)

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.get(f"/v1/medications/{product.id}")

    assert response.status_code == 200
    payload = response.json()
    assert payload["id"] == str(product.id)
    assert payload["generic_name"] == "Dipirona"
    assert payload["active_ingredients"][0]["canonical_name"] == "Dipirona"
    assert payload["therapeutic_class"] == "Analgésicos"
    assert payload["product_type"] == "Referência"
    assert payload["professional_leaflet_url"].endswith(
        "?numeroRegistro=123456789"
    )

    returned_presentation = payload["presentations"][0]
    assert returned_presentation["calculation_ready"] is True
    assert returned_presentation["concentration"] == {
        "numerator_value": "500",
        "numerator_unit": "mg",
        "denominator_value": "1",
        "denominator_unit": "mL",
    }
    assert returned_presentation["routes"][0]["code"] == "IV"


@pytest.mark.asyncio
async def test_detail_fails_closed_when_calculation_ready_has_incomplete_concentration():
    inconsistent = _presentation(
        calculation_ready=True,
        complete_concentration=False,
    )
    product = _product(presentation=inconsistent)

    session = MagicMock()
    session.scalars = AsyncMock(return_value=FakeScalarResult([product]))
    app = _app_with_session(session)

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.get(f"/v1/medications/{product.id}")

    assert response.status_code == 503
    payload = response.json()
    assert payload["detail"]["code"] == "CLINICAL_DATA_INTEGRITY_ERROR"
    assert payload["detail"]["presentation_id"] == str(inconsistent.id)
    assert "presentations" not in payload


@pytest.mark.asyncio
async def test_sync_content_returns_versioned_active_release_with_etag_and_gzip():
    ingredient = _ingredient()
    active_presentation = _presentation(
        calculation_ready=True,
        complete_concentration=True,
    )
    inactive_presentation = _presentation(
        calculation_ready=False,
        complete_concentration=True,
    )
    inactive_presentation.is_active = False
    product = _product(presentation=active_presentation, ingredient=ingredient)
    product.presentations.append(inactive_presentation)

    session = MagicMock()
    session.scalars = AsyncMock(
        side_effect=[
            FakeScalarResult([product]),
            FakeScalarResult([]),
            FakeScalarResult([]),
            FakeScalarResult([]),
            FakeScalarResult([ingredient]),
        ]
    )

    app = create_app()

    async def override_db_session():
        yield session

    app.dependency_overrides[get_db_session] = override_db_session

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
        headers={"Accept-Encoding": "gzip"},
    ) as client:
        response = await client.get("/v1/sync/content")

        assert response.status_code == 200
        payload = response.json()
        assert payload["release_schema"] == "clinical-release-v1"
        assert payload["content_version"].startswith("clinical-release-v1-")
        assert len(payload["active_ingredients"]) == 1
        assert len(payload["medications"]) == 1
        assert len(payload["presentations"]) == 1
        assert payload["administration_guidance"] == []
        assert payload["incompatibilities"] == []
        assert payload["presentations"][0]["id"] == str(active_presentation.id)
        assert payload["presentations"][0]["calculation_ready"] is True
        assert response.headers["etag"] == f'"{payload["content_version"]}"'
        assert response.headers["x-clinical-release"] == payload["content_version"]
        assert response.headers.get("content-encoding") == "gzip"

        session.scalars = AsyncMock(
            side_effect=[
                FakeScalarResult([product]),
                FakeScalarResult([]),
                FakeScalarResult([]),
                FakeScalarResult([ingredient]),
            ]
        )
        not_modified = await client.get(
            "/v1/sync/content",
            headers={
                "Accept-Encoding": "gzip",
                "If-None-Match": response.headers["etag"],
            },
        )

    assert not_modified.status_code == 304
    assert not_modified.content == b""
    assert not_modified.headers["etag"] == response.headers["etag"]


@pytest.mark.asyncio
async def test_sync_content_fails_closed_on_inconsistent_calculation_ready_row():
    ingredient = _ingredient()
    inconsistent = _presentation(
        calculation_ready=True,
        complete_concentration=False,
    )
    product = _product(presentation=inconsistent, ingredient=ingredient)

    session = MagicMock()
    session.scalars = AsyncMock(
        side_effect=[
            FakeScalarResult([product]),
            FakeScalarResult([]),
            FakeScalarResult([]),
            FakeScalarResult([]),
            FakeScalarResult([ingredient]),
        ]
    )
    app = _app_with_session(session)

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.get("/v1/sync/content")

    assert response.status_code == 503
    payload = response.json()
    assert payload["detail"]["code"] == "CLINICAL_DATA_INTEGRITY_ERROR"
    assert payload["detail"]["presentation_id"] == str(inconsistent.id)


@pytest.mark.asyncio
async def test_sync_content_includes_verified_administration_and_incompatibility():
    ingredient = _ingredient("Amiodarona")
    target = _ingredient("Bicarbonato de sódio")
    presentation = _presentation(calculation_ready=True, complete_concentration=True)
    product = _product(presentation=presentation, ingredient=ingredient)
    route = presentation.route_links[0].route

    guidance = SimpleNamespace(
        id=uuid4(),
        presentation_id=presentation.id,
        route=route,
        administration_method="Carga intravenosa por bomba volumétrica",
        diluent_name="SG 5% (D5W)",
        diluent_volume_value=Decimal("100"),
        diluent_volume_unit="mL",
        resulting_total_volume_value=Decimal("100"),
        resulting_total_volume_unit="mL",
        administration_time_min_seconds=600,
        administration_time_max_seconds=600,
        instruction_text="150 mg em 100 mL de SG 5% por 10 minutos.",
        review_status="public_label_verified",
        clinical_version="cycle10-1.0.0",
        source_name="DailyMed / FDA prescribing information",
        source_url="https://dailymed.nlm.nih.gov/",
        calculator_formula_id="MED_INFUSION_ML_H",
        calculator_volume_ml=Decimal("100"),
        calculator_duration_minutes=Decimal("10"),
    )
    incompatibility = SimpleNamespace(
        id=uuid4(),
        active_ingredient_id=ingredient.id,
        incompatible_ingredient_id=target.id,
        interaction_type="y_site",
        severity="critical",
        description="Forma precipitado; usar linha separada.",
        review_status="public_label_verified",
        clinical_version="cycle10-1.0.0",
        source_name="DailyMed / FDA prescribing information",
        source_url="https://dailymed.nlm.nih.gov/",
    )

    session = MagicMock()
    session.scalars = AsyncMock(
        side_effect=[
            FakeScalarResult([product]),
            FakeScalarResult([guidance]),
            FakeScalarResult([incompatibility]),
            FakeScalarResult([]),
            FakeScalarResult([ingredient, target]),
        ]
    )
    app = _app_with_session(session)

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        response = await client.get("/v1/sync/content")

    assert response.status_code == 200
    payload = response.json()
    assert payload["administration_guidance"][0]["calculator_formula_id"] == (
        "MED_INFUSION_ML_H"
    )
    assert payload["administration_guidance"][0][
        "administration_time_min_minutes"
    ] == "10"
    assert payload["incompatibilities"][0]["severity"] == "critical"
    assert payload["incompatibilities"][0]["incompatible_ingredient_name"] == (
        "Bicarbonato de sódio"
    )
