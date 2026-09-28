from __future__ import annotations

import argparse
import asyncio
import json
import os
import uuid
from dataclasses import asdict, dataclass
from decimal import Decimal
from typing import Final

from sqlalchemy import delete, func, or_, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.db.models import (
    ActiveIngredient,
    AdministrationGuidance,
    Incompatibility,
    MedicationProductIngredient,
    Presentation,
    PresentationRoute,
    Route,
)


SEED_ID: Final = "CYCLE10_PUBLIC_LABEL_SEED"
CLINICAL_VERSION: Final = "cycle10-1.0.0"
UUID_NAMESPACE: Final = uuid.UUID("dd582e08-935e-4c09-a9c8-a95d31150b0a")


@dataclass(frozen=True)
class GuidanceSpec:
    key: str
    aliases: tuple[str, ...]
    administration_method: str
    instruction_text: str
    source_url: str
    diluent_name: str | None = None
    diluent_volume_ml: Decimal | None = None
    resulting_total_volume_ml: Decimal | None = None
    min_minutes: Decimal | None = None
    max_minutes: Decimal | None = None
    calculator_volume_ml: Decimal | None = None
    calculator_duration_minutes: Decimal | None = None


@dataclass(frozen=True)
class IncompatibilitySpec:
    source_key: str
    target_exact_names: tuple[str, ...]
    description: str
    source_url: str
    severity: str = "critical"
    interaction_type: str = "y_site"


@dataclass(frozen=True)
class SeedSummary:
    ingredient_groups_found: int
    presentation_guidance_rows: int
    incompatibility_rows: int
    skipped_groups_without_iv_presentation: tuple[str, ...]


GUIDANCE: Final = (
    GuidanceSpec(
        key="norepinephrine",
        aliases=(
            "hemitartarato de norepinefrina",
            "hemitartarato de norepinefrina monoidratada",
        ),
        administration_method="Infusão intravenosa contínua",
        diluent_name=(
            "SG 5% (D5W) ou solução de cloreto de sódio contendo 5% de dextrose"
        ),
        diluent_volume_ml=Decimal("1000"),
        instruction_text=(
            "Referência de preparo do rótulo público: adicionar 4 mg em 4 mL a "
            "1.000 mL de SG 5% ou solução de cloreto de sódio que contenha 5% "
            "de dextrose, produzindo 4 mcg/mL. Solução salina isolada não é "
            "recomendada. A velocidade é titulada à resposta hemodinâmica; "
            "confirme a quantidade de princípio ativo da apresentação "
            "selecionada antes do preparo."
        ),
        source_url=(
            "https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?"
            "setid=109aa5e6-4e42-4131-97b0-f24d3a4cb4e8"
        ),
        calculator_volume_ml=Decimal("1000"),
    ),
    GuidanceSpec(
        key="amiodarone",
        aliases=("cloridrato de amiodarona",),
        administration_method="Carga intravenosa por bomba volumétrica",
        diluent_name="SG 5% (D5W)",
        diluent_volume_ml=Decimal("100"),
        resulting_total_volume_ml=Decimal("100"),
        min_minutes=Decimal("10"),
        max_minutes=Decimal("10"),
        instruction_text=(
            "Carga inicial do rótulo público: 150 mg (3 mL da apresentação "
            "50 mg/mL) em 100 mL de SG 5%, infundidos em 10 minutos. Usar bomba "
            "volumétrica e observar as recomendações de acesso, recipiente e "
            "filtro do rótulo."
        ),
        source_url=(
            "https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?"
            "setid=304d0be4-0c13-4dbb-8ffb-b2e7caa7fb1e"
        ),
        calculator_volume_ml=Decimal("100"),
        calculator_duration_minutes=Decimal("10"),
    ),
    GuidanceSpec(
        key="ceftriaxone",
        aliases=("ceftriaxona",),
        administration_method="Infusão intravenosa",
        diluent_name="Diluente IV compatível sem cálcio (ex.: SG 5%)",
        min_minutes=Decimal("30"),
        max_minutes=Decimal("60"),
        instruction_text=(
            "Infundir por 30 minutos; em neonatos, o rótulo recomenda 60 "
            "minutos. Para apresentações em pó, a solução IV deve ser preparada "
            "e posteriormente diluída para concentração apropriada conforme o "
            "rótulo. Não usar Ringer, Hartmann ou outros diluentes contendo "
            "cálcio."
        ),
        source_url=(
            "https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?"
            "setid=ff8e830a-c288-46fb-9e19-ec2017943c07"
        ),
    ),
    GuidanceSpec(
        key="fentanyl",
        aliases=("citrato de fentanila", "fentanila", "fentanil"),
        administration_method="Administração intravenosa lenta — cenário do rótulo",
        min_minutes=Decimal("1"),
        max_minutes=Decimal("2"),
        instruction_text=(
            "No cenário de analgesia adicional como adjuvante de anestesia "
            "regional, o rótulo descreve 50 a 100 mcg (1 a 2 mL da apresentação "
            "50 mcg/mL) lentamente por via IV em 1 a 2 minutos. Dose, indicação "
            "e monitorização dependem do contexto anestésico; não extrapolar "
            "este tempo para outros esquemas."
        ),
        source_url=(
            "https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?"
            "audience=professional&setid=c5d40297-b769-48cc-9f84-f98b7a333507"
        ),
    ),
    GuidanceSpec(
        key="propofol",
        aliases=("propofol",),
        administration_method="Administração intravenosa titulada",
        diluent_name="SG 5% (D5W), somente se a diluição for necessária",
        instruction_text=(
            "A emulsão é fornecida pronta para uso. Se a diluição for "
            "necessária, o rótulo orienta usar somente SG 5% e não reduzir a "
            "concentração abaixo de 2 mg/mL. Não misturar previamente com outros "
            "agentes terapêuticos. A velocidade deve ser individualizada e "
            "titulada à resposta clínica."
        ),
        source_url=(
            "https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?"
            "setid=de351d5f-581d-4768-a4af-fbd8e5bce264"
        ),
    ),
)


INCOMPATIBILITIES: Final = (
    IncompatibilitySpec(
        source_key="amiodarone",
        target_exact_names=("bicarbonato de sodio",),
        description=(
            "INCOMPATIBILIDADE EM Y: amiodarona em SG 5% forma precipitado com "
            "bicarbonato de sódio. Se ambos forem necessários, utilizar linhas "
            "intravenosas separadas."
        ),
        source_url=GUIDANCE[1].source_url,
    ),
    IncompatibilitySpec(
        source_key="amiodarone",
        target_exact_names=("heparina sodica suina",),
        description=(
            "INCOMPATIBILIDADE EM Y: amiodarona em SG 5% forma precipitado com "
            "heparina sódica. Se ambos forem necessários, utilizar linhas "
            "intravenosas separadas."
        ),
        source_url=GUIDANCE[1].source_url,
    ),
    IncompatibilitySpec(
        source_key="ceftriaxone",
        target_exact_names=("cloreto de calcio di-hidratado",),
        description=(
            "BLOQUEIO EM Y: ceftriaxona não deve ser administrada "
            "simultaneamente com soluções IV contendo cálcio, incluindo "
            "infusões contínuas, porque pode ocorrer precipitação "
            "ceftriaxona-cálcio. Ringer e Hartmann não devem ser usados como "
            "diluentes. Em pacientes não neonatais, administração sequencial "
            "exige lavagem completa da linha com fluido compatível."
        ),
        source_url=(
            "https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?"
            "setid=86ec0a92-a552-4a6d-9125-a54f95e43392"
        ),
    ),
)


def _stable_uuid(kind: str, material: str) -> uuid.UUID:
    return uuid.uuid5(UUID_NAMESPACE, f"{kind}:{material}")


async def _ingredient_ids_for_aliases(
    session: AsyncSession,
    aliases: tuple[str, ...],
) -> set[uuid.UUID]:
    clauses = [
        ActiveIngredient.normalized_name.ilike(f"%{alias}%")
        for alias in aliases
    ]
    return set(
        (
            await session.scalars(
                select(ActiveIngredient.id).where(
                    ActiveIngredient.is_active.is_(True),
                    or_(*clauses),
                )
            )
        ).all()
    )


async def _iv_presentations_for_ingredients(
    session: AsyncSession,
    ingredient_ids: set[uuid.UUID],
) -> list[tuple[Presentation, Route]]:
    if not ingredient_ids:
        return []

    rows = (
        await session.execute(
            select(Presentation, Route)
            .join(
                MedicationProductIngredient,
                MedicationProductIngredient.medication_product_id
                == Presentation.medication_product_id,
            )
            .join(
                PresentationRoute,
                PresentationRoute.presentation_id == Presentation.id,
            )
            .join(Route, Route.id == PresentationRoute.route_id)
            .where(
                Presentation.is_active.is_(True),
                MedicationProductIngredient.active_ingredient_id.in_(ingredient_ids),
                Route.is_active.is_(True),
                Route.code == "IV",
            )
            .order_by(Presentation.id)
        )
    ).all()

    seen: set[uuid.UUID] = set()
    unique: list[tuple[Presentation, Route]] = []
    for presentation, route in rows:
        if presentation.id in seen:
            continue
        seen.add(presentation.id)
        unique.append((presentation, route))
    return unique


async def _seed_guidance(
    session: AsyncSession,
) -> tuple[dict[str, set[uuid.UUID]], int, tuple[str, ...]]:
    ingredient_groups: dict[str, set[uuid.UUID]] = {}
    inserted = 0
    skipped: list[str] = []

    await session.execute(
        delete(AdministrationGuidance).where(
            AdministrationGuidance.reviewed_by == SEED_ID,
        )
    )

    for spec in GUIDANCE:
        ingredient_ids = await _ingredient_ids_for_aliases(session, spec.aliases)
        ingredient_groups[spec.key] = ingredient_ids
        presentations = await _iv_presentations_for_ingredients(
            session,
            ingredient_ids,
        )
        if not presentations:
            skipped.append(spec.key)
            continue

        for presentation, route in presentations:
            min_seconds = (
                int(spec.min_minutes * Decimal(60))
                if spec.min_minutes is not None
                else None
            )
            max_seconds = (
                int(spec.max_minutes * Decimal(60))
                if spec.max_minutes is not None
                else None
            )
            row = AdministrationGuidance(
                id=_stable_uuid(
                    "administration-guidance",
                    f"{spec.key}:{presentation.id}:{route.id}:{CLINICAL_VERSION}",
                ),
                presentation_id=presentation.id,
                route_id=route.id,
                diluent_name=spec.diluent_name,
                diluent_volume_value=spec.diluent_volume_ml,
                diluent_volume_unit=(
                    "mL" if spec.diluent_volume_ml is not None else None
                ),
                resulting_total_volume_value=spec.resulting_total_volume_ml,
                resulting_total_volume_unit=(
                    "mL"
                    if spec.resulting_total_volume_ml is not None
                    else None
                ),
                administration_method=spec.administration_method,
                administration_time_min_seconds=min_seconds,
                administration_time_max_seconds=max_seconds,
                instruction_text=spec.instruction_text,
                review_status="public_label_verified",
                reviewed_by=SEED_ID,
                reviewed_at=func.now(),
                clinical_version=CLINICAL_VERSION,
                source_name="DailyMed / FDA prescribing information",
                source_url=spec.source_url,
                calculator_formula_id=(
                    "MED_INFUSION_ML_H"
                    if spec.calculator_volume_ml is not None
                    else None
                ),
                calculator_volume_ml=spec.calculator_volume_ml,
                calculator_duration_minutes=spec.calculator_duration_minutes,
                is_current=True,
            )
            session.add(row)
            inserted += 1

    await session.flush()
    return ingredient_groups, inserted, tuple(skipped)


async def _find_target_ingredients(
    session: AsyncSession,
    exact_names: tuple[str, ...],
) -> list[ActiveIngredient]:
    return list(
        (
            await session.scalars(
                select(ActiveIngredient)
                .where(
                    ActiveIngredient.is_active.is_(True),
                    ActiveIngredient.normalized_name.in_(exact_names),
                )
                .order_by(ActiveIngredient.normalized_name)
            )
        ).all()
    )


async def _seed_incompatibilities(
    session: AsyncSession,
    ingredient_groups: dict[str, set[uuid.UUID]],
) -> int:
    inserted = 0

    for spec in INCOMPATIBILITIES:
        source_ids = ingredient_groups.get(spec.source_key, set())
        if not source_ids:
            continue
        targets = await _find_target_ingredients(
            session,
            spec.target_exact_names,
        )
        for source_id in sorted(source_ids, key=str):
            for target in targets:
                if source_id == target.id:
                    continue
                stable_id = _stable_uuid(
                    "incompatibility",
                    f"{source_id}:{target.id}:{spec.interaction_type}",
                )
                stmt = (
                    pg_insert(Incompatibility)
                    .values(
                        id=stable_id,
                        active_ingredient_id=source_id,
                        incompatible_ingredient_id=target.id,
                        interaction_type=spec.interaction_type,
                        severity=spec.severity,
                        description=spec.description,
                        review_status="public_label_verified",
                        reviewed_by=SEED_ID,
                        reviewed_at=func.now(),
                        clinical_version=CLINICAL_VERSION,
                        source_name="DailyMed / FDA prescribing information",
                        source_url=spec.source_url,
                        is_current=True,
                    )
                    .on_conflict_do_update(
                        index_elements=[
                            Incompatibility.active_ingredient_id,
                            Incompatibility.incompatible_ingredient_id,
                            Incompatibility.interaction_type,
                        ],
                        set_={
                            "severity": spec.severity,
                            "description": spec.description,
                            "review_status": "public_label_verified",
                            "reviewed_by": SEED_ID,
                            "reviewed_at": func.now(),
                            "clinical_version": CLINICAL_VERSION,
                            "source_name": "DailyMed / FDA prescribing information",
                            "source_url": spec.source_url,
                            "is_current": True,
                            "updated_at": func.now(),
                        },
                    )
                )
                await session.execute(stmt)
                inserted += 1

    await session.flush()
    return inserted


async def seed_critical_drugs(session: AsyncSession) -> SeedSummary:
    ingredient_groups, guidance_count, skipped = await _seed_guidance(session)
    incompatibility_count = await _seed_incompatibilities(
        session,
        ingredient_groups,
    )

    missing_groups = [
        spec.key
        for spec in GUIDANCE
        if not ingredient_groups.get(spec.key)
    ]
    if missing_groups:
        raise RuntimeError(
            "Critical ingredient groups missing from canonical data: "
            + ", ".join(missing_groups)
        )

    if skipped:
        raise RuntimeError(
            "Critical drugs have no active IV presentation: "
            + ", ".join(skipped)
        )

    return SeedSummary(
        ingredient_groups_found=sum(
            1 for ids in ingredient_groups.values() if ids
        ),
        presentation_guidance_rows=guidance_count,
        incompatibility_rows=incompatibility_count,
        skipped_groups_without_iv_presentation=skipped,
    )


async def async_main(args: argparse.Namespace) -> int:
    database_url = args.database_url or os.getenv("DATABASE_URL")
    if not database_url:
        raise RuntimeError("DATABASE_URL is required")
    if not database_url.startswith("postgresql+asyncpg://"):
        raise RuntimeError("DATABASE_URL must use the postgresql+asyncpg driver")

    engine = create_async_engine(database_url, pool_pre_ping=True)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    try:
        async with session_factory() as session:
            async with session.begin():
                summary = await seed_critical_drugs(session)
        print(json.dumps(asdict(summary), ensure_ascii=False, indent=2))
        return 0
    finally:
        await engine.dispose()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Seed source-traceable administration guidance and Y-site "
            "incompatibilities for five critical/emergency medicines."
        )
    )
    parser.add_argument(
        "--database-url",
        default=None,
        help="Overrides DATABASE_URL.",
    )
    return parser


def main() -> int:
    return asyncio.run(async_main(build_parser().parse_args()))


if __name__ == "__main__":
    raise SystemExit(main())
