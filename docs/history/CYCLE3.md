# Cycle 3 — API contracts + Clinical Calculation Core

## Included

- `backend/app/api/schemas.py`: Pydantic v2 public contracts.
- `backend/app/api/router.py`: FastAPI routes for quick search and medication detail.
- `backend/app/db/models.py`: Cycle 2 SQLAlchemy model copied here only so this package is self-contained.
- `mobile/lib/core/calculation/calculation_core.dart`: deterministic offline `MED_DOSE_MG_TO_ML` v1.
- `mobile/test/calculation_core_test.dart`: clinical unit tests, including fail-closed cases.
- `mobile/pubspec.yaml`: exact Flutter 3.47.5 and decimal arithmetic dependency.
- `.github/workflows/clinical_core_tests.yml`: PR gate workflow targeting `main`.

## Required PostgreSQL capability

The search stub uses PostgreSQL `pg_trgm` (`%` similarity operator), matching the indexes already defined in the Cycle 2 model:

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
```

## Required FastAPI app wiring

At startup, configure an `async_sessionmaker` on `app.state.db_sessionmaker`.
The route module deliberately does not create the engine or read secrets.

## Required GitHub repository rule

A failing Actions job only *blocks merge* when the repository requires that status check.
For branch `main`, enable a branch protection/ruleset and require the status check:

`clinical-core-tests`

Prefer also enabling "Require branches to be up to date before merging" and preventing bypass for the protected branch.

## Clinical rounding policy

V1 does **not** silently round recurring decimal results. It returns the explicit error
`roundingPolicyRequired`. A versioned rounding policy should be added only after clinical/product validation.
