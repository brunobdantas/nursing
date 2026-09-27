from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    MetaData,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    Uuid,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


# -----------------------------------------------------------------------------
# Naming convention: keeps Alembic migrations deterministic and readable.
# -----------------------------------------------------------------------------
NAMING_CONVENTION = {
    "ix": "ix_%(table_name)s_%(column_0_name)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)


class UUIDPrimaryKeyMixin:
    id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )


# =============================================================================
# RAW LAYER
# Purpose: immutable-ish snapshots and source metadata exactly as ingested.
# =============================================================================


class SourceSystem(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "source_system"
    __table_args__ = (
        CheckConstraint(
            "authority_level BETWEEN 0 AND 100",
            name="source_system_authority_level_range",
        ),
        {"schema": "raw"},
    )

    code: Mapped[str] = mapped_column(String(40), nullable=False, unique=True)
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    country_code: Mapped[str | None] = mapped_column(String(2))
    base_url: Mapped[str | None] = mapped_column(String(500))
    terms_url: Mapped[str | None] = mapped_column(String(500))

    # Suggested semantics: ANVISA=100, DailyMed/openFDA lower.
    authority_level: Mapped[int] = mapped_column(Integer, nullable=False, default=50)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    snapshots: Mapped[list["SourceSnapshot"]] = relationship(
        back_populates="source_system",
        cascade="all, delete-orphan",
    )


class SourceSnapshot(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "source_snapshot"
    __table_args__ = (
        UniqueConstraint(
            "source_system_id",
            "checksum_sha256",
            name="uq_source_snapshot_source_checksum",
        ),
        Index("ix_source_snapshot_retrieved_at", "retrieved_at"),
        Index("ix_source_snapshot_dataset_name", "dataset_name"),
        {"schema": "raw"},
    )

    source_system_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("raw.source_system.id", ondelete="RESTRICT"),
        nullable=False,
        index=True,
    )

    dataset_name: Mapped[str] = mapped_column(String(160), nullable=False)
    source_version: Mapped[str | None] = mapped_column(String(120))
    source_last_modified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    retrieved_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    checksum_sha256: Mapped[str] = mapped_column(String(64), nullable=False)
    raw_object_uri: Mapped[str] = mapped_column(String(1000), nullable=False)
    etl_version: Mapped[str] = mapped_column(String(80), nullable=False)
    schema_version: Mapped[str | None] = mapped_column(String(80))

    # raw metadata from headers/catalogs, never used as clinical truth directly.
    snapshot_metadata: Mapped[dict[str, Any] | None] = mapped_column(JSONB)

    source_system: Mapped[SourceSystem] = relationship(back_populates="snapshots")
    assertions: Mapped[list["SourceAssertion"]] = relationship(
        back_populates="source_snapshot",
        cascade="all, delete-orphan",
    )


# =============================================================================
# STAGING LAYER
# Purpose: parsed/normalized assertions from each snapshot before canonical merge.
# =============================================================================


class SourceAssertion(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "source_assertion"
    __table_args__ = (
        Index(
            "ix_source_assertion_lookup",
            "entity_type",
            "attribute_name",
            "external_record_id",
        ),
        Index("ix_source_assertion_snapshot", "source_snapshot_id"),
        Index("ix_source_assertion_content_hash", "content_hash"),
        {"schema": "staging"},
    )

    source_snapshot_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("raw.source_snapshot.id", ondelete="CASCADE"),
        nullable=False,
    )

    # Identifier in the source dataset/API, if one exists.
    external_record_id: Mapped[str | None] = mapped_column(String(255))

    # Examples: medication_product, presentation, route, administration_guidance.
    entity_type: Mapped[str] = mapped_column(String(80), nullable=False)

    # Stable identifying fields from the source, e.g. registration number + presentation.
    entity_key: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)

    # Example: "brand_name", "route", "diluent_volume".
    attribute_name: Mapped[str] = mapped_column(String(120), nullable=False)

    # Keep both a searchable scalar and a typed structured representation.
    value_text: Mapped[str | None] = mapped_column(Text)
    value_json: Mapped[dict[str, Any] | list[Any] | None] = mapped_column(JSONB)
    unit: Mapped[str | None] = mapped_column(String(40))
    language_code: Mapped[str | None] = mapped_column(String(10))

    # Provenance locator inside the source (section, path, URL, line, page etc.).
    source_locator: Mapped[dict[str, Any] | None] = mapped_column(JSONB)

    # Hash over the normalized assertion payload for diff/deduplication.
    content_hash: Mapped[str] = mapped_column(String(64), nullable=False)

    source_snapshot: Mapped[SourceSnapshot] = relationship(back_populates="assertions")
    provenance_links: Mapped[list["FieldProvenance"]] = relationship(
        back_populates="source_assertion"
    )


# =============================================================================
# CANONICAL LAYER
# Purpose: stable internal representation of medicines, products and presentations.
# =============================================================================


class ActiveIngredient(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "active_ingredient"
    __table_args__ = (
        UniqueConstraint("normalized_name", name="uq_active_ingredient_normalized_name"),
        Index(
            "ix_active_ingredient_normalized_name_trgm",
            "normalized_name",
            postgresql_using="gin",
            postgresql_ops={"normalized_name": "gin_trgm_ops"},
        ),
        {"schema": "canonical"},
    )

    canonical_name: Mapped[str] = mapped_column(String(1000), nullable=False)
    normalized_name: Mapped[str] = mapped_column(String(1000), nullable=False)
    atc_code: Mapped[str | None] = mapped_column(String(20), index=True)
    cas_number: Mapped[str | None] = mapped_column(String(32), index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    product_links: Mapped[list["MedicationProductIngredient"]] = relationship(
        back_populates="active_ingredient",
        cascade="all, delete-orphan",
    )


class MedicationProduct(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "medication_product"
    __table_args__ = (
        UniqueConstraint(
            "anvisa_registration_number",
            name="uq_medication_product_anvisa_registration",
        ),
        Index("ix_medication_product_brand_exact", "normalized_brand_name"),
        Index("ix_medication_product_generic_exact", "normalized_generic_name"),
        Index(
            "ix_medication_product_brand_trgm",
            "normalized_brand_name",
            postgresql_using="gin",
            postgresql_ops={"normalized_brand_name": "gin_trgm_ops"},
        ),
        Index(
            "ix_medication_product_generic_trgm",
            "normalized_generic_name",
            postgresql_using="gin",
            postgresql_ops={"normalized_generic_name": "gin_trgm_ops"},
        ),
        {"schema": "canonical"},
    )

    brand_name: Mapped[str | None] = mapped_column(String(255))
    normalized_brand_name: Mapped[str | None] = mapped_column(String(255))

    generic_name: Mapped[str] = mapped_column(String(500), nullable=False)
    normalized_generic_name: Mapped[str] = mapped_column(String(500), nullable=False)

    anvisa_registration_number: Mapped[str | None] = mapped_column(String(40))
    manufacturer_name: Mapped[str | None] = mapped_column(String(255), index=True)
    regulatory_status: Mapped[str | None] = mapped_column(String(80), index=True)
    therapeutic_class: Mapped[str | None] = mapped_column(String(255))
    product_type: Mapped[str | None] = mapped_column(String(160))
    country_code: Mapped[str] = mapped_column(String(2), nullable=False, default="BR")
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    ingredient_links: Mapped[list["MedicationProductIngredient"]] = relationship(
        back_populates="medication_product",
        cascade="all, delete-orphan",
    )
    presentations: Mapped[list["Presentation"]] = relationship(
        back_populates="medication_product",
        cascade="all, delete-orphan",
    )


class MedicationProductIngredient(TimestampMixin, Base):
    """Auxiliary relation required to correctly support combination products."""

    __tablename__ = "medication_product_ingredient"
    __table_args__ = (
        UniqueConstraint(
            "medication_product_id",
            "active_ingredient_id",
            name="uq_medication_product_ingredient_pair",
        ),
        {"schema": "canonical"},
    )

    medication_product_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("canonical.medication_product.id", ondelete="CASCADE"),
        primary_key=True,
    )
    active_ingredient_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("canonical.active_ingredient.id", ondelete="RESTRICT"),
        primary_key=True,
    )
    sequence_order: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    ingredient_role: Mapped[str] = mapped_column(
        String(30), nullable=False, default="active"
    )

    medication_product: Mapped[MedicationProduct] = relationship(
        back_populates="ingredient_links"
    )
    active_ingredient: Mapped[ActiveIngredient] = relationship(
        back_populates="product_links"
    )


class DosageForm(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "dosage_form"
    __table_args__ = (
        UniqueConstraint("code", name="uq_dosage_form_code"),
        UniqueConstraint("normalized_name", name="uq_dosage_form_normalized_name"),
        {"schema": "canonical"},
    )

    code: Mapped[str] = mapped_column(String(40), nullable=False)
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    normalized_name: Mapped[str] = mapped_column(String(160), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    presentations: Mapped[list["Presentation"]] = relationship(
        back_populates="dosage_form"
    )


class Route(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "route"
    __table_args__ = (
        UniqueConstraint("code", name="uq_route_code"),
        UniqueConstraint("normalized_name", name="uq_route_normalized_name"),
        {"schema": "canonical"},
    )

    code: Mapped[str] = mapped_column(String(30), nullable=False)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    normalized_name: Mapped[str] = mapped_column(String(120), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    presentation_links: Mapped[list["PresentationRoute"]] = relationship(
        back_populates="route",
        cascade="all, delete-orphan",
    )
    administration_guidance: Mapped[list["AdministrationGuidance"]] = relationship(
        back_populates="route"
    )
    reconstitution_rules: Mapped[list["ReconstitutionRule"]] = relationship(
        back_populates="route"
    )


class Presentation(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "presentation"
    __table_args__ = (
        UniqueConstraint(
            "medication_product_id",
            "external_presentation_code",
            name="uq_presentation_product_external_code",
        ),
        CheckConstraint(
            "concentration_value IS NULL OR concentration_value > 0",
            name="presentation_positive_concentration",
        ),
        CheckConstraint(
            "concentration_denominator_value IS NULL OR concentration_denominator_value > 0",
            name="presentation_positive_denominator",
        ),
        Index("ix_presentation_product", "medication_product_id"),
        Index("ix_presentation_dosage_form", "dosage_form_id"),
        {"schema": "canonical"},
    )

    medication_product_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("canonical.medication_product.id", ondelete="CASCADE"),
        nullable=False,
    )
    dosage_form_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("canonical.dosage_form.id", ondelete="RESTRICT"),
        nullable=False,
    )

    external_presentation_code: Mapped[str | None] = mapped_column(String(120))
    description: Mapped[str] = mapped_column(Text, nullable=False)

    # Human-readable regulatory strength; always retained even if not calculator-ready.
    strength_text: Mapped[str | None] = mapped_column(String(500))

    # Structured concentration used ONLY when clinically unambiguous and validated.
    concentration_value: Mapped[Decimal | None] = mapped_column(Numeric(18, 8))
    concentration_unit: Mapped[str | None] = mapped_column(String(40))
    concentration_denominator_value: Mapped[Decimal | None] = mapped_column(
        Numeric(18, 8)
    )
    concentration_denominator_unit: Mapped[str | None] = mapped_column(String(40))

    package_quantity: Mapped[Decimal | None] = mapped_column(Numeric(18, 8))
    package_unit: Mapped[str | None] = mapped_column(String(40))

    # Safety gate: calculations must not auto-enable from raw parsed text alone.
    calculation_ready: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    regulatory_status: Mapped[str | None] = mapped_column(String(80), index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    medication_product: Mapped[MedicationProduct] = relationship(
        back_populates="presentations"
    )
    dosage_form: Mapped[DosageForm] = relationship(back_populates="presentations")
    route_links: Mapped[list["PresentationRoute"]] = relationship(
        back_populates="presentation",
        cascade="all, delete-orphan",
    )
    administration_guidance: Mapped[list["AdministrationGuidance"]] = relationship(
        back_populates="presentation",
        cascade="all, delete-orphan",
    )
    reconstitution_rules: Mapped[list["ReconstitutionRule"]] = relationship(
        back_populates="presentation",
        cascade="all, delete-orphan",
    )


class PresentationRoute(TimestampMixin, Base):
    __tablename__ = "presentation_route"
    __table_args__ = ({"schema": "canonical"},)

    presentation_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("canonical.presentation.id", ondelete="CASCADE"),
        primary_key=True,
    )
    route_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("canonical.route.id", ondelete="RESTRICT"),
        primary_key=True,
    )

    presentation: Mapped[Presentation] = relationship(back_populates="route_links")
    route: Mapped[Route] = relationship(back_populates="presentation_links")


# =============================================================================
# CURATED LAYER
# Purpose: clinically reviewed operational knowledge used by the app.
# =============================================================================


class AdministrationGuidance(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "administration_guidance"
    __table_args__ = (
        CheckConstraint(
            "administration_time_min_seconds IS NULL OR administration_time_min_seconds >= 0",
            name="min_time_nonnegative",
        ),
        CheckConstraint(
            "administration_time_max_seconds IS NULL OR administration_time_max_seconds >= 0",
            name="max_time_nonnegative",
        ),
        CheckConstraint(
            "administration_time_min_seconds IS NULL OR administration_time_max_seconds IS NULL "
            "OR administration_time_min_seconds <= administration_time_max_seconds",
            name="time_range_valid",
        ),
        Index(
            "ix_administration_guidance_presentation_route",
            "presentation_id",
            "route_id",
        ),
        Index("ix_administration_guidance_review_status", "review_status"),
        {"schema": "curated"},
    )

    presentation_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("canonical.presentation.id", ondelete="CASCADE"),
        nullable=False,
    )
    route_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("canonical.route.id", ondelete="RESTRICT"),
        nullable=False,
    )

    administration_method: Mapped[str | None] = mapped_column(String(160))
    administration_time_min_seconds: Mapped[int | None] = mapped_column(Integer)
    administration_time_max_seconds: Mapped[int | None] = mapped_column(Integer)
    instruction_text: Mapped[str] = mapped_column(Text, nullable=False)

    review_status: Mapped[str] = mapped_column(
        String(30), nullable=False, default="draft"
    )
    reviewed_by: Mapped[str | None] = mapped_column(String(160))
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    clinical_version: Mapped[str | None] = mapped_column(String(80))
    is_current: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    presentation: Mapped[Presentation] = relationship(
        back_populates="administration_guidance"
    )
    route: Mapped[Route] = relationship(back_populates="administration_guidance")


class ReconstitutionRule(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "reconstitution_rule"
    __table_args__ = (
        CheckConstraint(
            "diluent_volume_value IS NULL OR diluent_volume_value > 0",
            name="positive_diluent_volume",
        ),
        CheckConstraint(
            "resulting_volume_value IS NULL OR resulting_volume_value > 0",
            name="positive_resulting_volume",
        ),
        CheckConstraint(
            "resulting_concentration_value IS NULL OR resulting_concentration_value > 0",
            name="positive_result_concentration",
        ),
        Index(
            "ix_reconstitution_rule_presentation_route",
            "presentation_id",
            "route_id",
        ),
        Index("ix_reconstitution_rule_review_status", "review_status"),
        {"schema": "curated"},
    )

    presentation_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("canonical.presentation.id", ondelete="CASCADE"),
        nullable=False,
    )
    route_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("canonical.route.id", ondelete="RESTRICT")
    )

    diluent_name: Mapped[str] = mapped_column(String(255), nullable=False)
    diluent_volume_value: Mapped[Decimal | None] = mapped_column(Numeric(18, 8))
    diluent_volume_unit: Mapped[str | None] = mapped_column(String(40))

    resulting_volume_value: Mapped[Decimal | None] = mapped_column(Numeric(18, 8))
    resulting_volume_unit: Mapped[str | None] = mapped_column(String(40))

    resulting_concentration_value: Mapped[Decimal | None] = mapped_column(
        Numeric(18, 8)
    )
    resulting_concentration_unit: Mapped[str | None] = mapped_column(String(40))
    resulting_concentration_denominator_value: Mapped[Decimal | None] = mapped_column(
        Numeric(18, 8)
    )
    resulting_concentration_denominator_unit: Mapped[str | None] = mapped_column(
        String(40)
    )

    instruction_text: Mapped[str] = mapped_column(Text, nullable=False)

    review_status: Mapped[str] = mapped_column(
        String(30), nullable=False, default="draft"
    )
    reviewed_by: Mapped[str | None] = mapped_column(String(160))
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    clinical_version: Mapped[str | None] = mapped_column(String(80))
    is_current: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    presentation: Mapped[Presentation] = relationship(
        back_populates="reconstitution_rules"
    )
    route: Mapped[Route | None] = relationship(back_populates="reconstitution_rules")


class FieldProvenance(UUIDPrimaryKeyMixin, TimestampMixin, Base):
    """
    Links one curated/canonical field to one source assertion.

    This is intentionally polymorphic because one provenance table must be able to
    address fields from several schemas/tables. Referential integrity for the target
    row is therefore enforced by the application/service layer (or an optional DB
    trigger), while source_assertion itself remains a real foreign key.
    """

    __tablename__ = "field_provenance"
    __table_args__ = (
        UniqueConstraint(
            "target_layer",
            "target_entity_type",
            "target_entity_id",
            "target_field_name",
            "source_assertion_id",
            name="uq_field_provenance_target_assertion",
        ),
        CheckConstraint(
            "confidence IS NULL OR (confidence >= 0 AND confidence <= 1)",
            name="confidence_range",
        ),
        Index(
            "ix_field_provenance_target",
            "target_layer",
            "target_entity_type",
            "target_entity_id",
            "target_field_name",
        ),
        Index("ix_field_provenance_source_assertion", "source_assertion_id"),
        {"schema": "curated"},
    )

    source_assertion_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("staging.source_assertion.id", ondelete="RESTRICT"),
        nullable=False,
    )

    # Expected values for MVP: "canonical" or "curated".
    target_layer: Mapped[str] = mapped_column(String(20), nullable=False)

    # Table/domain name, e.g. presentation, administration_guidance.
    target_entity_type: Mapped[str] = mapped_column(String(80), nullable=False)
    target_entity_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), nullable=False)
    target_field_name: Mapped[str] = mapped_column(String(120), nullable=False)

    is_primary: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    confidence: Mapped[Decimal | None] = mapped_column(Numeric(5, 4))
    review_status: Mapped[str] = mapped_column(
        String(30), nullable=False, default="pending", index=True
    )
    reviewed_by: Mapped[str | None] = mapped_column(String(160))
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    note: Mapped[str | None] = mapped_column(Text)

    source_assertion: Mapped[SourceAssertion] = relationship(
        back_populates="provenance_links"
    )
