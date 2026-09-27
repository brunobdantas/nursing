from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from enum import StrEnum
from typing import Annotated
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


class ApiModel(BaseModel):
    """Base contract for public API responses."""

    model_config = ConfigDict(
        from_attributes=True,
        extra="forbid",
        str_strip_whitespace=True,
    )


class SearchEntityType(StrEnum):
    ACTIVE_INGREDIENT = "active_ingredient"
    MEDICATION_PRODUCT = "medication_product"


class SearchMatchType(StrEnum):
    EXACT = "exact"
    PREFIX = "prefix"
    CONTAINS = "contains"
    APPROXIMATE = "approximate"


class SearchResult(ApiModel):
    id: UUID
    entity_type: SearchEntityType
    display_name: str
    secondary_name: str | None = None
    match_type: SearchMatchType
    score: Annotated[float, Field(ge=0.0, le=1.0)]
    is_approximate: bool = False
    has_calculation_ready_presentation: bool = False


class MedicationSearchResponse(ApiModel):
    query: str
    items: list[SearchResult]
    returned: Annotated[int, Field(ge=0)]


class ActiveIngredientSummary(ApiModel):
    id: UUID
    canonical_name: str
    atc_code: str | None = None


class DosageFormSummary(ApiModel):
    id: UUID
    code: str
    name: str


class RouteSummary(ApiModel):
    id: UUID
    code: str
    name: str


class ConcentrationData(ApiModel):
    """
    Structured concentration exactly as validated in the canonical layer.

    Example: 500 mg / 1 mL is represented as:
      numerator_value=500
      numerator_unit="mg"
      denominator_value=1
      denominator_unit="mL"
    """

    numerator_value: Annotated[Decimal, Field(gt=0)]
    numerator_unit: str
    denominator_value: Annotated[Decimal, Field(gt=0)]
    denominator_unit: str


class PresentationDetail(ApiModel):
    id: UUID
    external_presentation_code: str | None = None
    description: str
    strength_text: str | None = None
    dosage_form: DosageFormSummary
    routes: list[RouteSummary]
    concentration: ConcentrationData | None = None
    package_quantity: Decimal | None = None
    package_unit: str | None = None
    calculation_ready: bool
    regulatory_status: str | None = None

    @model_validator(mode="after")
    def calculation_ready_requires_structured_concentration(self) -> "PresentationDetail":
        # API-level fail-closed invariant: the mobile app must never receive a
        # calculator-enabled presentation without a complete structured concentration.
        if self.calculation_ready and self.concentration is None:
            raise ValueError(
                "calculation_ready=true requires a complete structured concentration"
            )
        return self


class MedicationDetailResponse(ApiModel):
    id: UUID
    brand_name: str | None = None
    generic_name: str
    anvisa_registration_number: str | None = None
    manufacturer_name: str | None = None
    regulatory_status: str | None = None
    therapeutic_class: str | None = None
    product_type: str | None = None
    professional_leaflet_url: str | None = None
    active_ingredients: list[ActiveIngredientSummary]
    presentations: list[PresentationDetail]


class SyncActiveIngredient(ApiModel):
    id: UUID
    canonical_name: str
    normalized_name: str
    atc_code: str | None = None


class SyncMedicationProduct(ApiModel):
    id: UUID
    brand_name: str | None = None
    normalized_brand_name: str | None = None
    generic_name: str
    normalized_generic_name: str
    anvisa_registration_number: str | None = None
    manufacturer_name: str | None = None
    regulatory_status: str | None = None
    therapeutic_class: str | None = None
    product_type: str | None = None
    professional_leaflet_url: str | None = None
    active_ingredient_ids: list[UUID]


class SyncPresentation(ApiModel):
    id: UUID
    medication_product_id: UUID
    external_presentation_code: str | None = None
    description: str
    strength_text: str | None = None
    dosage_form: DosageFormSummary
    routes: list[RouteSummary]
    concentration: ConcentrationData | None = None
    package_quantity: Decimal | None = None
    package_unit: str | None = None
    calculation_ready: bool
    regulatory_status: str | None = None

    @model_validator(mode="after")
    def sync_calculation_ready_requires_concentration(self) -> "SyncPresentation":
        if self.calculation_ready and self.concentration is None:
            raise ValueError(
                "sync calculation_ready=true requires structured concentration"
            )
        return self


class SyncContentResponse(ApiModel):
    release_schema: str = "clinical-release-v1"
    content_version: str
    generated_at: datetime
    active_ingredients: list[SyncActiveIngredient]
    medications: list[SyncMedicationProduct]
    presentations: list[SyncPresentation]
