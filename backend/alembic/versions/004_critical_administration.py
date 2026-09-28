"""Add curated administration dilution fields and Y-site incompatibilities.

Revision ID: 004_critical_administration
Revises: 003_cmed_enrichment
Create Date: 2026-09-28
"""
from __future__ import annotations

from typing import Sequence

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID


revision: str = "004_critical_administration"
down_revision: str | None = "003_cmed_enrichment"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "administration_guidance",
        sa.Column("diluent_name", sa.String(length=255), nullable=True),
        schema="curated",
    )
    op.add_column(
        "administration_guidance",
        sa.Column("diluent_volume_value", sa.Numeric(18, 8), nullable=True),
        schema="curated",
    )
    op.add_column(
        "administration_guidance",
        sa.Column("diluent_volume_unit", sa.String(length=40), nullable=True),
        schema="curated",
    )
    op.add_column(
        "administration_guidance",
        sa.Column("resulting_total_volume_value", sa.Numeric(18, 8), nullable=True),
        schema="curated",
    )
    op.add_column(
        "administration_guidance",
        sa.Column("resulting_total_volume_unit", sa.String(length=40), nullable=True),
        schema="curated",
    )
    op.add_column(
        "administration_guidance",
        sa.Column("source_name", sa.String(length=160), nullable=True),
        schema="curated",
    )
    op.add_column(
        "administration_guidance",
        sa.Column("source_url", sa.String(length=1000), nullable=True),
        schema="curated",
    )
    op.add_column(
        "administration_guidance",
        sa.Column("calculator_formula_id", sa.String(length=80), nullable=True),
        schema="curated",
    )
    op.add_column(
        "administration_guidance",
        sa.Column("calculator_volume_ml", sa.Numeric(18, 8), nullable=True),
        schema="curated",
    )
    op.add_column(
        "administration_guidance",
        sa.Column("calculator_duration_minutes", sa.Numeric(18, 8), nullable=True),
        schema="curated",
    )

    op.create_check_constraint(
        "ck_administration_guidance_administration_diluent_volume_positive",
        "administration_guidance",
        "diluent_volume_value IS NULL OR diluent_volume_value > 0",
        schema="curated",
    )
    op.create_check_constraint(
        "ck_administration_guidance_administration_total_volume_positive",
        "administration_guidance",
        "resulting_total_volume_value IS NULL OR resulting_total_volume_value > 0",
        schema="curated",
    )
    op.create_check_constraint(
        "ck_administration_guidance_administration_calculator_volume_positive",
        "administration_guidance",
        "calculator_volume_ml IS NULL OR calculator_volume_ml > 0",
        schema="curated",
    )
    op.create_check_constraint(
        "ck_administration_guidance_administration_calculator_duration_positive",
        "administration_guidance",
        "calculator_duration_minutes IS NULL OR calculator_duration_minutes > 0",
        schema="curated",
    )

    op.create_table(
        "incompatibility",
        sa.Column("id", UUID(as_uuid=True), nullable=False),
        sa.Column("active_ingredient_id", UUID(as_uuid=True), nullable=False),
        sa.Column("incompatible_ingredient_id", UUID(as_uuid=True), nullable=False),
        sa.Column("interaction_type", sa.String(length=40), nullable=False),
        sa.Column("severity", sa.String(length=20), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("review_status", sa.String(length=30), nullable=False),
        sa.Column("reviewed_by", sa.String(length=160), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("clinical_version", sa.String(length=80), nullable=True),
        sa.Column("source_name", sa.String(length=160), nullable=True),
        sa.Column("source_url", sa.String(length=1000), nullable=True),
        sa.Column("is_current", sa.Boolean(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.CheckConstraint(
            "severity IN ('critical', 'major', 'moderate', 'minor', 'unknown')",
            name="ck_incompatibility_incompatibility_severity_allowed",
        ),
        sa.ForeignKeyConstraint(
            ["active_ingredient_id"],
            ["canonical.active_ingredient.id"],
            name="fk_incompatibility_active_ingredient_id",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["incompatible_ingredient_id"],
            ["canonical.active_ingredient.id"],
            name="fk_incompatibility_incompatible_ingredient_id",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_incompatibility"),
        sa.UniqueConstraint(
            "active_ingredient_id",
            "incompatible_ingredient_id",
            "interaction_type",
            name="uq_incompatibility_pair_type",
        ),
        schema="curated",
    )
    op.create_index(
        "ix_incompatibility_active_ingredient",
        "incompatibility",
        ["active_ingredient_id"],
        schema="curated",
    )
    op.create_index(
        "ix_incompatibility_incompatible_ingredient",
        "incompatibility",
        ["incompatible_ingredient_id"],
        schema="curated",
    )
    op.create_index(
        "ix_incompatibility_review_status",
        "incompatibility",
        ["review_status"],
        schema="curated",
    )


def downgrade() -> None:
    op.drop_index(
        "ix_incompatibility_review_status",
        table_name="incompatibility",
        schema="curated",
    )
    op.drop_index(
        "ix_incompatibility_incompatible_ingredient",
        table_name="incompatibility",
        schema="curated",
    )
    op.drop_index(
        "ix_incompatibility_active_ingredient",
        table_name="incompatibility",
        schema="curated",
    )
    op.drop_table("incompatibility", schema="curated")

    op.drop_constraint(
        "ck_administration_guidance_administration_calculator_duration_positive",
        "administration_guidance",
        schema="curated",
        type_="check",
    )
    op.drop_constraint(
        "ck_administration_guidance_administration_calculator_volume_positive",
        "administration_guidance",
        schema="curated",
        type_="check",
    )
    op.drop_constraint(
        "ck_administration_guidance_administration_total_volume_positive",
        "administration_guidance",
        schema="curated",
        type_="check",
    )
    op.drop_constraint(
        "ck_administration_guidance_administration_diluent_volume_positive",
        "administration_guidance",
        schema="curated",
        type_="check",
    )

    for column in (
        "calculator_duration_minutes",
        "calculator_volume_ml",
        "calculator_formula_id",
        "source_url",
        "source_name",
        "resulting_total_volume_unit",
        "resulting_total_volume_value",
        "diluent_volume_unit",
        "diluent_volume_value",
        "diluent_name",
    ):
        op.drop_column("administration_guidance", column, schema="curated")
