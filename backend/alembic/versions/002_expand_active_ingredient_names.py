"""Expand active ingredient names for long ANVISA combinations.

Revision ID: 002_expand_ingredient_names
Revises: 001_initial_schema
Create Date: 2026-09-27
"""
from __future__ import annotations

from typing import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "002_expand_ingredient_names"
down_revision: str | None = "001_initial_schema"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.alter_column(
        "active_ingredient",
        "canonical_name",
        schema="canonical",
        existing_type=sa.String(length=255),
        type_=sa.String(length=1000),
        existing_nullable=False,
    )
    op.alter_column(
        "active_ingredient",
        "normalized_name",
        schema="canonical",
        existing_type=sa.String(length=255),
        type_=sa.String(length=1000),
        existing_nullable=False,
    )


def downgrade() -> None:
    # Downgrade is intentionally guarded. Long source-derived combination names
    # must never be silently truncated to fit the old schema.
    op.execute(
        """
        DO $$
        BEGIN
          IF EXISTS (
            SELECT 1
            FROM canonical.active_ingredient
            WHERE length(canonical_name) > 255
               OR length(normalized_name) > 255
          ) THEN
            RAISE EXCEPTION
              'Cannot downgrade: active ingredient names exceed 255 characters';
          END IF;
        END
        $$;
        """
    )
    op.alter_column(
        "active_ingredient",
        "normalized_name",
        schema="canonical",
        existing_type=sa.String(length=1000),
        type_=sa.String(length=255),
        existing_nullable=False,
    )
    op.alter_column(
        "active_ingredient",
        "canonical_name",
        schema="canonical",
        existing_type=sa.String(length=1000),
        type_=sa.String(length=255),
        existing_nullable=False,
    )
