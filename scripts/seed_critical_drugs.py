from __future__ import annotations

"""Repository-level entrypoint for the Cycle 10 critical-drug seed.

The implementation lives with the FastAPI backend so it can import the
SQLAlchemy models directly. Keeping this thin wrapper at scripts/ preserves the
documented operational command:

    python scripts/seed_critical_drugs.py

DATABASE_URL must point to the migrated PostgreSQL database.
"""

from pathlib import Path
import runpy
import sys


ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "backend"
IMPLEMENTATION = BACKEND / "scripts" / "seed_critical_drugs.py"

if str(BACKEND) not in sys.path:
    sys.path.insert(0, str(BACKEND))

runpy.run_path(str(IMPLEMENTATION), run_name="__main__")
