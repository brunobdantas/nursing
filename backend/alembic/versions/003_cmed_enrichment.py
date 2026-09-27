"""Add CMED enrichment fields to medication products.

Revision ID: 003_cmed_enrichment
Revises: 002_expand_ingredient_names
Create Date: 2026-09-27
"""
from __future__ import annotations

from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "003_cmed_enrichment"
down_revision: str | None = "002_expand_ingredient_names"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "medication_product",
        sa.Column("therapeutic_class", sa.String(length=255), nullable=True),
        schema="canonical",
    )
    op.add_column(
        "medication_product",
        sa.Column("product_type", sa.String(length=160), nullable=True),
        schema="canonical",
    )


def downgrade() -> None:
    op.drop_column("medication_product", "product_type", schema="canonical")
    op.drop_column("medication_product", "therapeutic_class", schema="canonical")
