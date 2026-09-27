from __future__ import annotations

import hashlib
import json
import unicodedata
from collections.abc import AsyncIterator
from datetime import datetime, timezone
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status
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
    SyncActiveIngredient,
    SyncContentResponse,
    SyncMedicationProduct,
    SyncPresentation,
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


def _professional_leaflet_url(registration: str | None) -> str | None:
    if not registration:
        return None
    digits = "".join(char for char in registration if char.isdigit())
    if not digits:
        return None
    return (
        "https://consultas.anvisa.gov.br/#/bulario/q/"
        f"?numeroRegistro={digits}"
    )


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
    "/sync/content",
    response_model=SyncContentResponse,
    tags=["sync"],
    summary="Dump clínico versionado para uso offline",
)
async def get_sync_content(
    session: DbSession,
    request: Request,
    response: Response,
) -> SyncContentResponse | Response:
    """
    Return the complete active clinical release used by the offline-first app.

    The content version is a deterministic hash of the clinical payload. Clients
    send it back through If-None-Match; unchanged releases return HTTP 304 without
    re-downloading the JSON body.
    """

    product_stmt = (
        select(MedicationProduct)
        .where(MedicationProduct.is_active.is_(True))
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
        .order_by(MedicationProduct.normalized_generic_name, MedicationProduct.id)
    )

    products = list((await session.scalars(product_stmt)).unique().all())
    referenced_ingredient_ids = {
        link.active_ingredient.id
        for product in products
        for link in product.ingredient_links
        if link.active_ingredient.is_active
    }
    if referenced_ingredient_ids:
        ingredient_stmt = (
            select(ActiveIngredient)
            .where(
                ActiveIngredient.is_active.is_(True),
                ActiveIngredient.id.in_(referenced_ingredient_ids),
            )
            .order_by(ActiveIngredient.normalized_name, ActiveIngredient.id)
        )
        ingredients = list((await session.scalars(ingredient_stmt)).all())
    else:
        ingredients = []

    sync_ingredients = [
        SyncActiveIngredient(
            id=ingredient.id,
            canonical_name=ingredient.canonical_name,
            normalized_name=ingredient.normalized_name,
            atc_code=ingredient.atc_code,
        )
        for ingredient in ingredients
    ]

    sync_medications: list[SyncMedicationProduct] = []
    sync_presentations: list[SyncPresentation] = []

    for product in products:
        ingredient_ids = [
            link.active_ingredient.id
            for link in sorted(
                product.ingredient_links,
                key=lambda link: link.sequence_order,
            )
            if link.active_ingredient.is_active
        ]
        sync_medications.append(
            SyncMedicationProduct(
                id=product.id,
                brand_name=product.brand_name,
                normalized_brand_name=product.normalized_brand_name,
                generic_name=product.generic_name,
                normalized_generic_name=product.normalized_generic_name,
                anvisa_registration_number=product.anvisa_registration_number,
                manufacturer_name=product.manufacturer_name,
                regulatory_status=product.regulatory_status,
                therapeutic_class=product.therapeutic_class,
                product_type=product.product_type,
                professional_leaflet_url=_professional_leaflet_url(
                    product.anvisa_registration_number
                ),
                active_ingredient_ids=ingredient_ids,
            )
        )

        for presentation in sorted(
            (item for item in product.presentations if item.is_active),
            key=lambda item: (item.description.casefold(), str(item.id)),
        ):
            concentration_complete = all(
                value is not None
                for value in (
                    presentation.concentration_value,
                    presentation.concentration_unit,
                    presentation.concentration_denominator_value,
                    presentation.concentration_denominator_unit,
                )
            )
            concentration: ConcentrationData | None = None
            if concentration_complete:
                concentration = ConcentrationData(
                    numerator_value=presentation.concentration_value,
                    numerator_unit=presentation.concentration_unit,
                    denominator_value=presentation.concentration_denominator_value,
                    denominator_unit=presentation.concentration_denominator_unit,
                )

            if presentation.calculation_ready and concentration is None:
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail={
                        "code": "CLINICAL_DATA_INTEGRITY_ERROR",
                        "message": (
                            "Apresentação ativa marcada como calculation_ready sem "
                            "concentração estruturada completa."
                        ),
                        "presentation_id": str(presentation.id),
                    },
                )

            sync_presentations.append(
                SyncPresentation(
                    id=presentation.id,
                    medication_product_id=product.id,
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
                        for link in sorted(
                            presentation.route_links,
                            key=lambda link: (link.route.name.casefold(), str(link.route.id)),
                        )
                    ],
                    concentration=concentration,
                    package_quantity=presentation.package_quantity,
                    package_unit=presentation.package_unit,
                    calculation_ready=bool(presentation.calculation_ready),
                    regulatory_status=presentation.regulatory_status,
                )
            )

    release_basis = {
        "release_schema": "clinical-release-v1",
        "active_ingredients": [
            item.model_dump(mode="json") for item in sync_ingredients
        ],
        "medications": [item.model_dump(mode="json") for item in sync_medications],
        "presentations": [
            item.model_dump(mode="json") for item in sync_presentations
        ],
    }
    release_bytes = json.dumps(
        release_basis,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    digest = hashlib.sha256(release_bytes).hexdigest()
    content_version = f"clinical-release-v1-{digest[:24]}"
    etag = f'"{content_version}"'
    common_headers = {
        "ETag": etag,
        "Cache-Control": "no-cache",
        "X-Clinical-Release": content_version,
    }

    if request.headers.get("if-none-match") == etag:
        return Response(status_code=status.HTTP_304_NOT_MODIFIED, headers=common_headers)

    for key, value in common_headers.items():
        response.headers[key] = value

    return SyncContentResponse(
        release_schema="clinical-release-v1",
        content_version=content_version,
        generated_at=datetime.now(timezone.utc),
        active_ingredients=sync_ingredients,
        medications=sync_medications,
        presentations=sync_presentations,
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
    for presentation in (
        item for item in product.presentations if item.is_active
    ):
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
        therapeutic_class=product.therapeutic_class,
        product_type=product.product_type,
        professional_leaflet_url=_professional_leaflet_url(
            product.anvisa_registration_number
        ),
        active_ingredients=ingredient_summaries,
        presentations=presentations,
    )
