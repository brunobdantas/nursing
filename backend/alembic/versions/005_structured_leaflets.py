"""Add deduplicated structured professional leaflets.

Revision ID: 005_structured_leaflets
Revises: 004_critical_administration
Create Date: 2026-09-28
"""
from __future__ import annotations

from typing import Sequence

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID


revision: str = "005_structured_leaflets"
down_revision: str | None = "004_critical_administration"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "professional_leaflet",
        sa.Column("id", UUID(as_uuid=True), nullable=False),
        sa.Column("source_name", sa.String(length=160), nullable=False),
        sa.Column("source_document_id", sa.String(length=120), nullable=False),
        sa.Column("source_version", sa.String(length=80), nullable=False),
        sa.Column(
            "source_language",
            sa.String(length=16),
            nullable=False,
            server_default="en-US",
        ),
        sa.Column("source_url", sa.String(length=1000), nullable=False),
        sa.Column("source_effective_date", sa.String(length=32), nullable=True),
        sa.Column("indications_text", sa.Text(), nullable=True),
        sa.Column("dosage_administration_text", sa.Text(), nullable=True),
        sa.Column("contraindications_text", sa.Text(), nullable=True),
        sa.Column("warnings_precautions_text", sa.Text(), nullable=True),
        sa.Column("adverse_reactions_text", sa.Text(), nullable=True),
        sa.Column("drug_interactions_text", sa.Text(), nullable=True),
        sa.Column("specific_populations_text", sa.Text(), nullable=True),
        sa.Column("overdosage_text", sa.Text(), nullable=True),
        sa.Column("description_text", sa.Text(), nullable=True),
        sa.Column("clinical_pharmacology_text", sa.Text(), nullable=True),
        sa.Column("how_supplied_storage_text", sa.Text(), nullable=True),
        sa.Column("patient_counseling_text", sa.Text(), nullable=True),
        sa.Column(
            "review_status",
            sa.String(length=30),
            nullable=False,
            server_default="public_label_verified",
        ),
        sa.Column("reviewed_by", sa.String(length=160), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("clinical_version", sa.String(length=80), nullable=True),
        sa.Column(
            "is_current",
            sa.Boolean(),
            nullable=False,
            server_default=sa.true(),
        ),
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
        sa.PrimaryKeyConstraint("id", name="pk_professional_leaflet"),
        sa.UniqueConstraint(
            "source_name",
            "source_document_id",
            "source_version",
            name="uq_professional_leaflet_source_version",
        ),
        schema="curated",
    )
    op.create_index(
        "ix_professional_leaflet_source_document",
        "professional_leaflet",
        ["source_document_id"],
        schema="curated",
    )
    op.create_index(
        "ix_professional_leaflet_review_status",
        "professional_leaflet",
        ["review_status"],
        schema="curated",
    )

    op.create_table(
        "medication_leaflet_link",
        sa.Column("medication_product_id", UUID(as_uuid=True), nullable=False),
        sa.Column("professional_leaflet_id", UUID(as_uuid=True), nullable=False),
        sa.Column(
            "relation_type",
            sa.String(length=40),
            nullable=False,
            server_default="active_ingredient_reference",
        ),
        sa.Column(
            "review_status",
            sa.String(length=30),
            nullable=False,
            server_default="public_label_verified",
        ),
        sa.Column("reviewed_by", sa.String(length=160), nullable=True),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "is_current",
            sa.Boolean(),
            nullable=False,
            server_default=sa.true(),
        ),
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
        sa.ForeignKeyConstraint(
            ["medication_product_id"],
            ["canonical.medication_product.id"],
            name="fk_medication_leaflet_link_medication_product_id",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["professional_leaflet_id"],
            ["curated.professional_leaflet.id"],
            name="fk_medication_leaflet_link_professional_leaflet_id",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint(
            "medication_product_id",
            "professional_leaflet_id",
            name="pk_medication_leaflet_link",
        ),
        schema="curated",
    )
    op.create_index(
        "ix_medication_leaflet_link_product",
        "medication_leaflet_link",
        ["medication_product_id"],
        schema="curated",
    )
    op.create_index(
        "ix_medication_leaflet_link_leaflet",
        "medication_leaflet_link",
        ["professional_leaflet_id"],
        schema="curated",
    )
    op.create_index(
        "ix_medication_leaflet_link_review_status",
        "medication_leaflet_link",
        ["review_status"],
        schema="curated",
    )


def downgrade() -> None:
    op.drop_index(
        "ix_medication_leaflet_link_review_status",
        table_name="medication_leaflet_link",
        schema="curated",
    )
    op.drop_index(
        "ix_medication_leaflet_link_leaflet",
        table_name="medication_leaflet_link",
        schema="curated",
    )
    op.drop_index(
        "ix_medication_leaflet_link_product",
        table_name="medication_leaflet_link",
        schema="curated",
    )
    op.drop_table("medication_leaflet_link", schema="curated")

    op.drop_index(
        "ix_professional_leaflet_review_status",
        table_name="professional_leaflet",
        schema="curated",
    )
    op.drop_index(
        "ix_professional_leaflet_source_document",
        table_name="professional_leaflet",
        schema="curated",
    )
    op.drop_table("professional_leaflet", schema="curated")
