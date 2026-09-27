from __future__ import annotations

import unicodedata
from collections.abc import AsyncIterator
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker
from sqlalchemy.orm import selectinload

from app.api.schemas import (
    ActiveIngredientSummary,
    ConcentrationData,
    DosageFormSummary,
    MedicationDetailResponse,
    MedicationSearchResponse,
    PresentationDetail,
    RouteSummary,
    SearchEntityType,
    SearchMatchType,
    SearchResult,
)
from app.db.models import (
    ActiveIngredient,
    MedicationProduct,
    MedicationProductIngredient,
    Presentation,
    PresentationRoute,
)

router = APIRouter(prefix="/v1", tags=["medications"])


async def get_db_session(request: Request) -> AsyncIterator[AsyncSession]:
    """
    Application-level DB dependency.

    The FastAPI app startup must set:
        app.state.db_sessionmaker = async_sessionmaker(...)

    Keeping engine creation outside this module makes the API contract testable and
    avoids coupling routes to secrets/configuration.
    """

    factory = getattr(request.app.state, "db_sessionmaker", None)
    if factory is None or not isinstance(factory, async_sessionmaker):
        raise RuntimeError("app.state.db_sessionmaker was not configured")

    async with factory() as session:
        yield session


DbSession = Annotated[AsyncSession, Depends(get_db_session)]


def _normalize_search_term(value: str) -> str:
    value = unicodedata.normalize("NFKD", value)
    value = "".join(char for char in value if not unicodedata.combining(char))
    return " ".join(value.casefold().split())


def _rank_match(candidate: str, query: str) -> tuple[SearchMatchType, float]:
    candidate_norm = _normalize_search_term(candidate)
    if candidate_norm == query:
        return SearchMatchType.EXACT, 1.0
    if candidate_norm.startswith(query):
        return SearchMatchType.PREFIX, 0.90
    if query in candidate_norm:
        return SearchMatchType.CONTAINS, 0.75
    return SearchMatchType.APPROXIMATE, 0.50


@router.get(
    "/medications/search",
    response_model=MedicationSearchResponse,
    summary="Busca rápida de medicamentos e princípios ativos",
)
async def search_medications(
    session: DbSession,
    q: Annotated[str, Query(min_length=2, max_length=120)],
    limit: Annotated[int, Query(ge=1, le=30)] = 20,
) -> MedicationSearchResponse:
    """
    Safety-oriented search contract.

    Exact/prefix/contains candidates are returned first. PostgreSQL pg_trgm is used
    only as a fallback candidate generator; approximate matches are explicitly marked
    so the mobile UI can render them as "resultado aproximado" and never auto-select.
    """

    normalized_q = _normalize_search_term(q)
    like_prefix = f"{normalized_q}%"
    like_contains = f"%{normalized_q}%"

    ingredient_stmt = (
        select(ActiveIngredient)
        .where(
            ActiveIngredient.is_active.is_(True),
            or_(
                ActiveIngredient.normalized_name == normalized_q,
                ActiveIngredient.normalized_name.ilike(like_prefix),
                ActiveIngredient.normalized_name.ilike(like_contains),
                ActiveIngredient.normalized_name.op("%")(
                    normalized_q
                ),  # pg_trgm similarity operator
            ),
        )
        .limit(limit)
    )

    product_stmt = (
        select(MedicationProduct)
        .options(selectinload(MedicationProduct.presentations))
        .where(
            MedicationProduct.is_active.is_(True),
            or_(
                MedicationProduct.normalized_brand_name == normalized_q,
                MedicationProduct.normalized_generic_name == normalized_q,
                MedicationProduct.normalized_brand_name.ilike(like_prefix),
                MedicationProduct.normalized_generic_name.ilike(like_prefix),
                MedicationProduct.normalized_brand_name.ilike(like_contains),
                MedicationProduct.normalized_generic_name.ilike(like_contains),
                MedicationProduct.normalized_brand_name.op("%")(
                    normalized_q
                ),
                MedicationProduct.normalized_generic_name.op("%")(
                    normalized_q
                ),
            ),
        )
        .limit(limit)
    )

    ingredients = (await session.scalars(ingredient_stmt)).all()
    products = (await session.scalars(product_stmt)).unique().all()

    items: list[SearchResult] = []

    for ingredient in ingredients:
        match_type, score = _rank_match(ingredient.canonical_name, normalized_q)
        items.append(
            SearchResult(
                id=ingredient.id,
                entity_type=SearchEntityType.ACTIVE_INGREDIENT,
                display_name=ingredient.canonical_name,
                secondary_name=None,
                match_type=match_type,
                score=score,
                is_approximate=match_type is SearchMatchType.APPROXIMATE,
                has_calculation_ready_presentation=False,
            )
        )

    for product in products:
        candidate_names = [product.generic_name]
        if product.brand_name:
            candidate_names.append(product.brand_name)

        ranked = [_rank_match(name, normalized_q) for name in candidate_names]
        match_type, score = max(ranked, key=lambda item: item[1])
        display_name = product.brand_name or product.generic_name
        secondary_name = product.generic_name if product.brand_name else None

        items.append(
            SearchResult(
                id=product.id,
                entity_type=SearchEntityType.MEDICATION_PRODUCT,
                display_name=display_name,
                secondary_name=secondary_name,
                match_type=match_type,
                score=score,
                is_approximate=match_type is SearchMatchType.APPROXIMATE,
                has_calculation_ready_presentation=any(
                    presentation.calculation_ready
                    for presentation in product.presentations
                ),
            )
        )

    items.sort(
        key=lambda item: (
            item.is_approximate,
            -item.score,
            item.display_name.casefold(),
        )
    )
    items = items[:limit]

    return MedicationSearchResponse(
        query=q,
        items=items,
        returned=len(items),
    )


@router.get(
    "/medications/{medication_product_id}",
    response_model=MedicationDetailResponse,
    summary="Detalhes operacionais do medicamento",
)
async def get_medication_detail(
    medication_product_id: UUID,
    session: DbSession,
) -> MedicationDetailResponse:
    stmt = (
        select(MedicationProduct)
        .where(
            MedicationProduct.id == medication_product_id,
            MedicationProduct.is_active.is_(True),
        )
        .options(
            selectinload(MedicationProduct.ingredient_links).selectinload(
                MedicationProductIngredient.active_ingredient
            ),
            selectinload(MedicationProduct.presentations).selectinload(
                Presentation.dosage_form
            ),
            selectinload(MedicationProduct.presentations)
            .selectinload(Presentation.route_links)
            .selectinload(PresentationRoute.route),
        )
    )

    product = (await session.scalars(stmt)).unique().one_or_none()
    if product is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Medicamento não encontrado.",
        )

    ingredient_summaries = [
        ActiveIngredientSummary(
            id=link.active_ingredient.id,
            canonical_name=link.active_ingredient.canonical_name,
            atc_code=link.active_ingredient.atc_code,
        )
        for link in sorted(product.ingredient_links, key=lambda link: link.sequence_order)
    ]

    presentations: list[PresentationDetail] = []
    for presentation in product.presentations:
        concentration: ConcentrationData | None = None
        concentration_complete = all(
            value is not None
            for value in (
                presentation.concentration_value,
                presentation.concentration_unit,
                presentation.concentration_denominator_value,
                presentation.concentration_denominator_unit,
            )
        )

        if concentration_complete:
            concentration = ConcentrationData(
                numerator_value=presentation.concentration_value,
                numerator_unit=presentation.concentration_unit,
                denominator_value=presentation.concentration_denominator_value,
                denominator_unit=presentation.concentration_denominator_unit,
            )

        # Fail closed if data drift ever produces an inconsistent canonical row.
        # We deliberately block the whole response instead of silently downgrading
        # calculation_ready, because an inconsistent clinical record must be visible
        # to operations and must never reach the mobile client as if it were healthy.
        if presentation.calculation_ready and concentration is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail={
                    "code": "CLINICAL_DATA_INTEGRITY_ERROR",
                    "message": (
                        "Apresentação marcada como calculation_ready sem "
                        "concentração estruturada completa."
                    ),
                    "presentation_id": str(presentation.id),
                },
            )

        calculation_ready = bool(presentation.calculation_ready)

        presentations.append(
            PresentationDetail(
                id=presentation.id,
                external_presentation_code=presentation.external_presentation_code,
                description=presentation.description,
                strength_text=presentation.strength_text,
                dosage_form=DosageFormSummary(
                    id=presentation.dosage_form.id,
                    code=presentation.dosage_form.code,
                    name=presentation.dosage_form.name,
                ),
                routes=[
                    RouteSummary(
                        id=link.route.id,
                        code=link.route.code,
                        name=link.route.name,
                    )
                    for link in presentation.route_links
                ],
                concentration=concentration,
                package_quantity=presentation.package_quantity,
                package_unit=presentation.package_unit,
                calculation_ready=calculation_ready,
                regulatory_status=presentation.regulatory_status,
            )
        )

    presentations.sort(key=lambda item: item.description.casefold())

    return MedicationDetailResponse(
        id=product.id,
        brand_name=product.brand_name,
        generic_name=product.generic_name,
        anvisa_registration_number=product.anvisa_registration_number,
        manufacturer_name=product.manufacturer_name,
        regulatory_status=product.regulatory_status,
        active_ingredients=ingredient_summaries,
        presentations=presentations,
    )
