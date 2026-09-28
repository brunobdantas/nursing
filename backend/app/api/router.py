from __future__ import annotations

import hashlib
import json
import unicodedata
from collections.abc import AsyncIterator
from datetime import datetime, timezone
from decimal import Decimal
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
    SyncAdministrationGuidance,
    SyncContentResponse,
    SyncIncompatibility,
    SyncMedicationLeafletLink,
    SyncMedicationProduct,
    SyncPresentation,
    SyncProfessionalLeaflet,
)
from app.db.models import (
    ActiveIngredient,
    AdministrationGuidance,
    Incompatibility,
    MedicationLeafletLink,
    MedicationProduct,
    MedicationProductIngredient,
    Presentation,
    PresentationRoute,
    ProfessionalLeaflet,
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

    product_ingredient_ids = {
        link.active_ingredient.id
        for product in products
        for link in product.ingredient_links
        if link.active_ingredient.is_active
    }
    product_ids = {product.id for product in products}
    active_presentation_ids = {
        presentation.id
        for product in products
        for presentation in product.presentations
        if presentation.is_active
    }

    if active_presentation_ids:
        guidance_stmt = (
            select(AdministrationGuidance)
            .options(selectinload(AdministrationGuidance.route))
            .where(
                AdministrationGuidance.is_current.is_(True),
                AdministrationGuidance.presentation_id.in_(active_presentation_ids),
                AdministrationGuidance.review_status.in_(
                    ("approved", "public_label_verified", "automated_validated")
                ),
            )
            .order_by(
                AdministrationGuidance.presentation_id,
                AdministrationGuidance.id,
            )
        )
        guidance_rows = list((await session.scalars(guidance_stmt)).all())
    else:
        guidance_rows = []

    if product_ingredient_ids:
        incompatibility_stmt = (
            select(Incompatibility)
            .where(
                Incompatibility.is_current.is_(True),
                Incompatibility.active_ingredient_id.in_(product_ingredient_ids),
                Incompatibility.review_status.in_(
                    ("approved", "public_label_verified", "automated_validated")
                ),
            )
            .order_by(
                Incompatibility.active_ingredient_id,
                Incompatibility.incompatible_ingredient_id,
                Incompatibility.id,
            )
        )
        incompatibility_rows = list(
            (await session.scalars(incompatibility_stmt)).all()
        )
    else:
        incompatibility_rows = []

    if product_ids:
        leaflet_stmt = (
            select(ProfessionalLeaflet)
            .join(
                MedicationLeafletLink,
                MedicationLeafletLink.professional_leaflet_id
                == ProfessionalLeaflet.id,
            )
            .options(selectinload(ProfessionalLeaflet.medication_links))
            .where(
                ProfessionalLeaflet.is_current.is_(True),
                ProfessionalLeaflet.review_status.in_(
                    ("approved", "public_label_verified", "automated_validated")
                ),
                MedicationLeafletLink.medication_product_id.in_(product_ids),
                MedicationLeafletLink.is_current.is_(True),
                MedicationLeafletLink.review_status.in_(
                    ("approved", "public_label_verified", "automated_validated")
                ),
            )
            .order_by(
                ProfessionalLeaflet.source_name,
                ProfessionalLeaflet.source_document_id,
                ProfessionalLeaflet.source_version,
            )
        )
        leaflet_rows = list(
            (await session.scalars(leaflet_stmt)).unique().all()
        )
    else:
        leaflet_rows = []

    referenced_ingredient_ids = set(product_ingredient_ids)
    referenced_ingredient_ids.update(
        item.incompatible_ingredient_id for item in incompatibility_rows
    )
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

    ingredient_by_id = {ingredient.id: ingredient for ingredient in ingredients}
    presentation_to_product_id = {
        presentation.id: product.id
        for product in products
        for presentation in product.presentations
        if presentation.is_active
    }

    sync_medications: list[SyncMedicationProduct] = []
    sync_presentations: list[SyncPresentation] = []
    sync_guidance: list[SyncAdministrationGuidance] = []
    sync_incompatibilities: list[SyncIncompatibility] = []
    sync_leaflets: list[SyncProfessionalLeaflet] = []
    sync_leaflet_links: list[SyncMedicationLeafletLink] = []

    for row in leaflet_rows:
        sync_leaflets.append(
            SyncProfessionalLeaflet(
                id=row.id,
                source_name=row.source_name,
                source_document_id=row.source_document_id,
                source_version=row.source_version,
                source_language=row.source_language,
                source_url=row.source_url,
                source_effective_date=row.source_effective_date,
                indications_text=row.indications_text,
                dosage_administration_text=row.dosage_administration_text,
                contraindications_text=row.contraindications_text,
                warnings_precautions_text=row.warnings_precautions_text,
                adverse_reactions_text=row.adverse_reactions_text,
                drug_interactions_text=row.drug_interactions_text,
                specific_populations_text=row.specific_populations_text,
                overdosage_text=row.overdosage_text,
                description_text=row.description_text,
                clinical_pharmacology_text=row.clinical_pharmacology_text,
                how_supplied_storage_text=row.how_supplied_storage_text,
                patient_counseling_text=row.patient_counseling_text,
                review_status=row.review_status,
                clinical_version=row.clinical_version,
            )
        )
        for link in sorted(
            (
                item
                for item in row.medication_links
                if item.medication_product_id in product_ids
                and item.is_current
                and item.review_status
                in ("approved", "public_label_verified", "automated_validated")
            ),
            key=lambda item: (str(item.medication_product_id), item.relation_type),
        ):
            sync_leaflet_links.append(
                SyncMedicationLeafletLink(
                    medication_product_id=link.medication_product_id,
                    professional_leaflet_id=row.id,
                    relation_type=link.relation_type,
                )
            )

    for row in guidance_rows:
        product_id = presentation_to_product_id.get(row.presentation_id)
        if product_id is None:
            continue
        sync_guidance.append(
            SyncAdministrationGuidance(
                id=row.id,
                medication_product_id=product_id,
                presentation_id=row.presentation_id,
                route=RouteSummary(
                    id=row.route.id,
                    code=row.route.code,
                    name=row.route.name,
                ),
                administration_method=row.administration_method,
                diluent_name=row.diluent_name,
                diluent_volume_value=row.diluent_volume_value,
                diluent_volume_unit=row.diluent_volume_unit,
                resulting_total_volume_value=row.resulting_total_volume_value,
                resulting_total_volume_unit=row.resulting_total_volume_unit,
                administration_time_min_minutes=(
                    Decimal(row.administration_time_min_seconds) / Decimal(60)
                    if row.administration_time_min_seconds is not None
                    else None
                ),
                administration_time_max_minutes=(
                    Decimal(row.administration_time_max_seconds) / Decimal(60)
                    if row.administration_time_max_seconds is not None
                    else None
                ),
                instruction_text=row.instruction_text,
                review_status=row.review_status,
                clinical_version=row.clinical_version,
                source_name=row.source_name,
                source_url=row.source_url,
                calculator_formula_id=row.calculator_formula_id,
                calculator_volume_ml=row.calculator_volume_ml,
                calculator_duration_minutes=row.calculator_duration_minutes,
            )
        )

    for row in incompatibility_rows:
        incompatible = ingredient_by_id.get(row.incompatible_ingredient_id)
        if incompatible is None:
            continue
        sync_incompatibilities.append(
            SyncIncompatibility(
                id=row.id,
                active_ingredient_id=row.active_ingredient_id,
                incompatible_ingredient_id=row.incompatible_ingredient_id,
                incompatible_ingredient_name=incompatible.canonical_name,
                interaction_type=row.interaction_type,
                severity=row.severity,
                description=row.description,
                review_status=row.review_status,
                clinical_version=row.clinical_version,
                source_name=row.source_name,
                source_url=row.source_url,
            )
        )

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
        "administration_guidance": [
            item.model_dump(mode="json") for item in sync_guidance
        ],
        "incompatibilities": [
            item.model_dump(mode="json") for item in sync_incompatibilities
        ],
        "professional_leaflets": [
            item.model_dump(mode="json") for item in sync_leaflets
        ],
        "medication_leaflet_links": [
            item.model_dump(mode="json") for item in sync_leaflet_links
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
        administration_guidance=sync_guidance,
        incompatibilities=sync_incompatibilities,
        professional_leaflets=sync_leaflets,
        medication_leaflet_links=sync_leaflet_links,
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
