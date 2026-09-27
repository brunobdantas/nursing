"""Initial four-layer clinical data schema.

Revision ID: 001_initial_schema
Revises: None
Create Date: 2026-09-26
"""
from __future__ import annotations

from typing import Sequence

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "001_initial_schema"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


TS = sa.DateTime(timezone=True)
UUID = sa.Uuid()


def _timestamps() -> tuple[sa.Column, sa.Column]:
    return (
        sa.Column("created_at", TS, server_default=sa.text("now()"), nullable=False),
        sa.Column("updated_at", TS, server_default=sa.text("now()"), nullable=False),
    )


def upgrade() -> None:
    # pg_trgm must exist before the GIN trigram indexes are created.
    op.execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    for schema in ("raw", "staging", "canonical", "curated"):
        op.execute(sa.text(f'CREATE SCHEMA IF NOT EXISTS "{schema}"'))

    # ------------------------------------------------------------------ RAW
    op.create_table(
        "source_system",
        sa.Column("id", UUID, nullable=False),
        sa.Column("code", sa.String(40), nullable=False),
        sa.Column("name", sa.String(160), nullable=False),
        sa.Column("country_code", sa.String(2), nullable=True),
        sa.Column("base_url", sa.String(500), nullable=True),
        sa.Column("terms_url", sa.String(500), nullable=True),
        sa.Column("authority_level", sa.Integer(), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        *_timestamps(),
        sa.CheckConstraint(
            "authority_level BETWEEN 0 AND 100",
            name="source_system_authority_level_range",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_source_system"),
        sa.UniqueConstraint("code", name="uq_source_system_code"),
        schema="raw",
    )

    op.create_table(
        "source_snapshot",
        sa.Column("id", UUID, nullable=False),
        sa.Column("source_system_id", UUID, nullable=False),
        sa.Column("dataset_name", sa.String(160), nullable=False),
        sa.Column("source_version", sa.String(120), nullable=True),
        sa.Column("source_last_modified_at", TS, nullable=True),
        sa.Column("retrieved_at", TS, server_default=sa.text("now()"), nullable=False),
        sa.Column("checksum_sha256", sa.String(64), nullable=False),
        sa.Column("raw_object_uri", sa.String(1000), nullable=False),
        sa.Column("etl_version", sa.String(80), nullable=False),
        sa.Column("schema_version", sa.String(80), nullable=True),
        sa.Column("snapshot_metadata", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        *_timestamps(),
        sa.ForeignKeyConstraint(
            ["source_system_id"],
            ["raw.source_system.id"],
            name="fk_source_snapshot_source_system_id",
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_source_snapshot"),
        sa.UniqueConstraint(
            "source_system_id",
            "checksum_sha256",
            name="uq_source_snapshot_source_checksum",
        ),
        schema="raw",
    )
    op.create_index(
        "ix_source_snapshot_source_system_id",
        "source_snapshot",
        ["source_system_id"],
        schema="raw",
    )
    op.create_index(
        "ix_source_snapshot_retrieved_at",
        "source_snapshot",
        ["retrieved_at"],
        schema="raw",
    )
    op.create_index(
        "ix_source_snapshot_dataset_name",
        "source_snapshot",
        ["dataset_name"],
        schema="raw",
    )

    # ------------------------------------------------------------------------ STAGING
    op.create_table(
        "source_assertion",
        sa.Column("id", UUID, nullable=False),
        sa.Column("source_snapshot_id", UUID, nullable=False),
        sa.Column("external_record_id", sa.String(255), nullable=True),
        sa.Column("entity_type", sa.String(80), nullable=False),
        sa.Column("entity_key", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("attribute_name", sa.String(120), nullable=False),
        sa.Column("value_text", sa.Text(), nullable=True),
        sa.Column("value_json", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("unit", sa.String(40), nullable=True),
        sa.Column("language_code", sa.String(10), nullable=True),
        sa.Column("source_locator", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("content_hash", sa.String(64), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(
            ["source_snapshot_id"],
            ["raw.source_snapshot.id"],
            name="fk_source_assertion_source_snapshot_id",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_source_assertion"),
        schema="staging",
    )
    op.create_index(
        "ix_source_assertion_lookup",
        "source_assertion",
        ["entity_type", "attribute_name", "external_record_id"],
        schema="staging",
    )
    op.create_index(
        "ix_source_assertion_snapshot",
        "source_assertion",
        ["source_snapshot_id"],
        schema="staging",
    )
    op.create_index(
        "ix_source_assertion_content_hash",
        "source_assertion",
        ["content_hash"],
        schema="staging",
    )

    # -------------------------------------------------------------- CANONICAL
    op.create_table(
        "active_ingredient",
        sa.Column("id", UUID, nullable=False),
        sa.Column("canonical_name", sa.String(255), nullable=False),
        sa.Column("normalized_name", sa.String(255), nullable=False),
        sa.Column("atc_code", sa.String(20), nullable=True),
        sa.Column("cas_number", sa.String(32), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        *_timestamps(),
        sa.PrimaryKeyConstraint("id", name="pk_active_ingredient"),
        sa.UniqueConstraint(
            "normalized_name",
            name="uq_active_ingredient_normalized_name",
        ),
        schema="canonical",
    )
    op.create_index(
        "ix_active_ingredient_atc_code",
        "active_ingredient",
        ["atc_code"],
        schema="canonical",
    )
    op.create_index(
        "ix_active_ingredient_cas_number",
        "active_ingredient",
        ["cas_number"],
        schema="canonical",
    )
    op.create_index(
        "ix_active_ingredient_normalized_name_trgm",
        "active_ingredient",
        ["normalized_name"],
        unique=False,
        schema="canonical",
        postgresql_using="gin",
        postgresql_ops={"normalized_name": "gin_trgm_ops"},
    )

    op.create_table(
        "medication_product",
        sa.Column("id", UUID, nullable=False),
        sa.Column("brand_name", sa.String(255), nullable=True),
        sa.Column("normalized_brand_name", sa.String(255), nullable=True),
        sa.Column("generic_name", sa.String(500), nullable=False),
        sa.Column("normalized_generic_name", sa.String(500), nullable=False),
        sa.Column("anvisa_registration_number", sa.String(40), nullable=True),
        sa.Column("manufacturer_name", sa.String(255), nullable=True),
        sa.Column("regulatory_status", sa.String(80), nullable=True),
        sa.Column("country_code", sa.String(2), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        *_timestamps(),
        sa.PrimaryKeyConstraint("id", name="pk_medication_product"),
        sa.UniqueConstraint(
            "anvisa_registration_number",
            name="uq_medication_product_anvisa_registration",
        ),
        schema="canonical",
    )
    op.create_index(
        "ix_medication_product_brand_exact",
        "medication_product",
        ["normalized_brand_name"],
        schema="canonical",
    )
    op.create_index(
        "ix_medication_product_generic_exact",
        "medication_product",
        ["normalized_generic_name"],
        schema="canonical",
    )
    op.create_index(
        "ix_medication_product_brand_trgm",
        "medication_product",
        ["normalized_brand_name"],
        schema="canonical",
        postgresql_using="gin",
        postgresql_ops={"normalized_brand_name": "gin_trgm_ops"},
    )
    op.create_index(
        "ix_medication_product_generic_trgm",
        "medication_product",
        ["normalized_generic_name"],
        schema="canonical",
        postgresql_using="gin",
        postgresql_ops={"normalized_generic_name": "gin_trgm_ops"},
    )
    op.create_index(
        "ix_medication_product_manufacturer_name",
        "medication_product",
        ["manufacturer_name"],
        schema="canonical",
    )
    op.create_index(
        "ix_medication_product_regulatory_status",
        "medication_product",
        ["regulatory_status"],
        schema="canonical",
    )

    op.create_table(
        "dosage_form",
        sa.Column("id", UUID, nullable=False),
        sa.Column("code", sa.String(40), nullable=False),
        sa.Column("name", sa.String(160), nullable=False),
        sa.Column("normalized_name", sa.String(160), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        *_timestamps(),
        sa.PrimaryKeyConstraint("id", name="pk_dosage_form"),
        sa.UniqueConstraint("code", name="uq_dosage_form_code"),
        sa.UniqueConstraint(
            "normalized_name",
            name="uq_dosage_form_normalized_name",
        ),
        schema="canonical",
    )

    op.create_table(
        "route",
        sa.Column("id", UUID, nullable=False),
        sa.Column("code", sa.String(30), nullable=False),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("normalized_name", sa.String(120), nullable=False),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        *_timestamps(),
        sa.PrimaryKeyConstraint("id", name="pk_route"),
        sa.UniqueConstraint("code", name="uq_route_code"),
        sa.UniqueConstraint("normalized_name", name="uq_route_normalized_name"),
        schema="canonical",
    )

    op.create_table(
        "medication_product_ingredient",
        sa.Column("medication_product_id", UUID, nullable=False),
        sa.Column("active_ingredient_id", UUID, nullable=False),
        sa.Column("sequence_order", sa.Integer(), nullable=False),
        sa.Column("ingredient_role", sa.String(30), nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(
            ["medication_product_id"],
            ["canonical.medication_product.id"],
            name="fk_medication_product_ingredient_medication_product_id",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["active_ingredient_id"],
            ["canonical.active_ingredient.id"],
            name="fk_medication_product_ingredient_active_ingredient_id",
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint(
            "medication_product_id",
            "active_ingredient_id",
            name="pk_medication_product_ingredient",
        ),
        sa.UniqueConstraint(
            "medication_product_id",
            "active_ingredient_id",
            name="uq_medication_product_ingredient_pair",
        ),
        schema="canonical",
    )

    op.create_table(
        "presentation",
        sa.Column("id", UUID, nullable=False),
        sa.Column("medication_product_id", UUID, nullable=False),
        sa.Column("dosage_form_id", UUID, nullable=False),
        sa.Column("external_presentation_code", sa.String(120), nullable=True),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("strength_text", sa.String(500), nullable=True),
        sa.Column("concentration_value", sa.Numeric(18, 8), nullable=True),
        sa.Column("concentration_unit", sa.String(40), nullable=True),
        sa.Column("concentration_denominator_value", sa.Numeric(18, 8), nullable=True),
        sa.Column("concentration_denominator_unit", sa.String(40), nullable=True),
        sa.Column("package_quantity", sa.Numeric(18, 8), nullable=True),
        sa.Column("package_unit", sa.String(40), nullable=True),
        sa.Column("calculation_ready", sa.Boolean(), nullable=False),
        sa.Column("regulatory_status", sa.String(80), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False),
        *_timestamps(),
        sa.CheckConstraint(
            "concentration_value IS NULL OR concentration_value > 0",
            name="presentation_positive_concentration",
        ),
        sa.CheckConstraint(
            "concentration_denominator_value IS NULL OR concentration_denominator_value > 0",
            name="presentation_positive_denominator",
        ),
        sa.ForeignKeyConstraint(
            ["medication_product_id"],
            ["canonical.medication_product.id"],
            name="fk_presentation_medication_product_id",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["dosage_form_id"],
            ["canonical.dosage_form.id"],
            name="fk_presentation_dosage_form_id",
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_presentation"),
        sa.UniqueConstraint(
            "medication_product_id",
            "external_presentation_code",
            name="uq_presentation_product_external_code",
        ),
        schema="canonical",
    )
    op.create_index(
        "ix_presentation_product",
        "presentation",
        ["medication_product_id"],
        schema="canonical",
    )
    op.create_index(
        "ix_presentation_dosage_form",
        "presentation",
        ["dosage_form_id"],
        schema="canonical",
    )
    op.create_index(
        "ix_presentation_regulatory_status",
        "presentation",
        ["regulatory_status"],
        schema="canonical",
    )

    op.create_table(
        "presentation_route",
        sa.Column("presentation_id", UUID, nullable=False),
        sa.Column("route_id", UUID, nullable=False),
        *_timestamps(),
        sa.ForeignKeyConstraint(
            ["presentation_id"],
            ["canonical.presentation.id"],
            name="fk_presentation_route_presentation_id",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["route_id"],
            ["canonical.route.id"],
            name="fk_presentation_route_route_id",
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint(
            "presentation_id",
            "route_id",
            name="pk_presentation_route",
        ),
        schema="canonical",
    )

    # --------------------------------------------------------------- CURATED
    op.create_table(
        "administration_guidance",
        sa.Column("id", UUID, nullable=False),
        sa.Column("presentation_id", UUID, nullable=False),
        sa.Column("route_id", UUID, nullable=False),
        sa.Column("administration_method", sa.String(160), nullable=True),
        sa.Column("administration_time_min_seconds", sa.Integer(), nullable=True),
        sa.Column("administration_time_max_seconds", sa.Integer(), nullable=True),
        sa.Column("instruction_text", sa.Text(), nullable=False),
        sa.Column("review_status", sa.String(30), nullable=False),
        sa.Column("reviewed_by", sa.String(160), nullable=True),
        sa.Column("reviewed_at", TS, nullable=True),
        sa.Column("clinical_version", sa.String(80), nullable=True),
        sa.Column("is_current", sa.Boolean(), nullable=False),
        *_timestamps(),
        sa.CheckConstraint(
            "administration_time_min_seconds IS NULL OR administration_time_min_seconds >= 0",
            name="min_time_nonnegative",
        ),
        sa.CheckConstraint(
            "administration_time_max_seconds IS NULL OR administration_time_max_seconds >= 0",
            name="max_time_nonnegative",
        ),
        sa.CheckConstraint(
            "administration_time_min_seconds IS NULL OR administration_time_max_seconds IS NULL "
            "OR administration_time_min_seconds <= administration_time_max_seconds",
            name="time_range_valid",
        ),
        sa.ForeignKeyConstraint(
            ["presentation_id"],
            ["canonical.presentation.id"],
            name="fk_administration_guidance_presentation_id",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["route_id"],
            ["canonical.route.id"],
            name="fk_administration_guidance_route_id",
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_administration_guidance"),
        schema="curated",
    )
    op.create_index(
        "ix_administration_guidance_presentation_route",
        "administration_guidance",
        ["presentation_id", "route_id"],
        schema="curated",
    )
    op.create_index(
        "ix_administration_guidance_review_status",
        "administration_guidance",
        ["review_status"],
        schema="curated",
    )

    op.create_table(
        "reconstitution_rule",
        sa.Column("id", UUID, nullable=False),
        sa.Column("presentation_id", UUID, nullable=False),
        sa.Column("route_id", UUID, nullable=True),
        sa.Column("diluent_name", sa.String(255), nullable=False),
        sa.Column("diluent_volume_value", sa.Numeric(18, 8), nullable=True),
        sa.Column("diluent_volume_unit", sa.String(40), nullable=True),
        sa.Column("resulting_volume_value", sa.Numeric(18, 8), nullable=True),
        sa.Column("resulting_volume_unit", sa.String(40), nullable=True),
        sa.Column("resulting_concentration_value", sa.Numeric(18, 8), nullable=True),
        sa.Column("resulting_concentration_unit", sa.String(40), nullable=True),
        sa.Column("resulting_concentration_denominator_value", sa.Numeric(18, 8), nullable=True),
        sa.Column("resulting_concentration_denominator_unit", sa.String(40), nullable=True),
        sa.Column("instruction_text", sa.Text(), nullable=False),
        sa.Column("review_status", sa.String(30), nullable=False),
        sa.Column("reviewed_by", sa.String(160), nullable=True),
        sa.Column("reviewed_at", TS, nullable=True),
        sa.Column("clinical_version", sa.String(80), nullable=True),
        sa.Column("is_current", sa.Boolean(), nullable=False),
        *_timestamps(),
        sa.CheckConstraint(
            "diluent_volume_value IS NULL OR diluent_volume_value > 0",
            name="positive_diluent_volume",
        ),
        sa.CheckConstraint(
            "resulting_volume_value IS NULL OR resulting_volume_value > 0",
            name="positive_resulting_volume",
        ),
        sa.CheckConstraint(
            "resulting_concentration_value IS NULL OR resulting_concentration_value > 0",
            name="positive_result_concentration",
        ),
        sa.ForeignKeyConstraint(
            ["presentation_id"],
            ["canonical.presentation.id"],
            name="fk_reconstitution_rule_presentation_id",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["route_id"],
            ["canonical.route.id"],
            name="fk_reconstitution_rule_route_id",
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_reconstitution_rule"),
        schema="curated",
    )
    op.create_index(
        "ix_reconstitution_rule_presentation_route",
        "reconstitution_rule",
        ["presentation_id", "route_id"],
        schema="curated",
    )
    op.create_index(
        "ix_reconstitution_rule_review_status",
        "reconstitution_rule",
        ["review_status"],
        schema="curated",
    )

    op.create_table(
        "field_provenance",
        sa.Column("id", UUID, nullable=False),
        sa.Column("source_assertion_id", UUID, nullable=False),
        sa.Column("target_layer", sa.String(20), nullable=False),
        sa.Column("target_entity_type", sa.String(80), nullable=False),
        sa.Column("target_entity_id", UUID, nullable=False),
        sa.Column("target_field_name", sa.String(120), nullable=False),
        sa.Column("is_primary", sa.Boolean(), nullable=False),
        sa.Column("confidence", sa.Numeric(5, 4), nullable=True),
        sa.Column("review_status", sa.String(30), nullable=False),
        sa.Column("reviewed_by", sa.String(160), nullable=True),
        sa.Column("reviewed_at", TS, nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        *_timestamps(),
        sa.CheckConstraint(
            "confidence IS NULL OR (confidence >= 0 AND confidence <= 1)",
            name="confidence_range",
        ),
        sa.ForeignKeyConstraint(
            ["source_assertion_id"],
            ["staging.source_assertion.id"],
            name="fk_field_provenance_source_assertion_id",
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_field_provenance"),
        sa.UniqueConstraint(
            "target_layer",
            "target_entity_type",
            "target_entity_id",
            "target_field_name",
            "source_assertion_id",
            name="uq_field_provenance_target_assertion",
        ),
        schema="curated",
    )
    op.create_index(
        "ix_field_provenance_target",
        "field_provenance",
        ["target_layer", "target_entity_type", "target_entity_id", "target_field_name"],
        schema="curated",
    )
    op.create_index(
        "ix_field_provenance_source_assertion",
        "field_provenance",
        ["source_assertion_id"],
        schema="curated",
    )
    op.create_index(
        "ix_field_provenance_review_status",
        "field_provenance",
        ["review_status"],
        schema="curated",
    )


def downgrade() -> None:
    # Reverse dependency order.
    op.drop_table("field_provenance", schema="curated")
    op.drop_table("reconstitution_rule", schema="curated")
    op.drop_table("administration_guidance", schema="curated")

    op.drop_table("presentation_route", schema="canonical")
    op.drop_table("presentation", schema="canonical")
    op.drop_table("medication_product_ingredient", schema="canonical")
    op.drop_table("route", schema="canonical")
    op.drop_table("dosage_form", schema="canonical")
    op.drop_table("medication_product", schema="canonical")
    op.drop_table("active_ingredient", schema="canonical")

    op.drop_table("source_assertion", schema="staging")
    op.drop_table("source_snapshot", schema="raw")
    op.drop_table("source_system", schema="raw")

    for schema in ("curated", "canonical", "staging", "raw"):
        op.execute(sa.text(f'DROP SCHEMA IF EXISTS "{schema}"'))

    # Dedicated application database assumption. If pg_trgm is shared by other
    # applications in the same database, remove this line from the downgrade.
    op.execute("DROP EXTENSION IF EXISTS pg_trgm")
