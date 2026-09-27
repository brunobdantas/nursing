# Nursing

Aplicativo mobile de apoio a enfermeiros e técnicos de enfermagem, com foco em **Bulário Inteligente**, **administração segura de medicamentos** e **calculadoras clínicas determinísticas**.

> Status: MVP em desenvolvimento. Este repositório ainda não representa software validado para uso clínico em produção.

## Princípios

- **Safety by design:** falha fechada, unidades explícitas e memória de cálculo.
- **Calculation Core determinístico:** nenhuma IA generativa calcula dose.
- **Proveniência por atributo:** conteúdo clínico rastreável até fonte/snapshot.
- **Offline-first para cálculo:** motor executado localmente no dispositivo.
- **Sem dados de pacientes no MVP.**

## Stack

- Mobile: Flutter / Dart
- API: FastAPI / Pydantic
- ORM: SQLAlchemy 2.x
- Banco: PostgreSQL 18
- Migrações: Alembic
- ETL: Python + httpx + pandas
- CI/CD e governança: GitHub Actions + Dependabot + CODEOWNERS

## Estrutura

```text
nursing/
├── backend/
│   ├── alembic/
│   ├── app/api/
│   ├── app/db/
│   ├── scripts/etl_anvisa.py
│   └── tests/
├── mobile/
│   ├── lib/core/calculation/
│   └── test/
├── docs/
├── .github/
└── docker-compose.yml
```

## Arquitetura de dados

```text
RAW -> STAGING -> CANONICAL -> CURATED
```

A ANVISA é a fonte master brasileira. DailyMed e openFDA estão previstos como enriquecimento, sem substituir automaticamente a informação regulatória brasileira.

## Calculation Core V1

Fórmula disponível:

```text
MED_DOSE_MG_TO_ML v1.0.0
```

Contrato suportado no V1:

```text
dose: mg
concentração: mg/mL
resultado: mL
```

Sem conversões implícitas de unidade e sem arredondamento clínico automático ainda.

## Backend local

```bash
cp backend/.env.example backend/.env
docker compose up -d postgres
cd backend
pip install -r requirements.txt
alembic -c alembic.ini upgrade head
pytest -q
```

## ETL ANVISA

Com o banco migrado e `DATABASE_URL` configurado:

```bash
cd backend
python scripts/etl_anvisa.py
```

O ETL registra `source_system`, cria `source_snapshot` idempotente por SHA-256 e popula `staging.source_assertion` preservando o registro de origem.

## Mobile

```bash
cd mobile
flutter pub get
flutter test
```

## Documentação

- [PRD do MVP](docs/PRD_MVP.md)
- [Arquitetura](docs/ARCHITECTURE.md)
- [Governança GitHub](docs/GITHUB_GOVERNANCE.md)
- [ADR — Calculation Core](docs/adr/0001-clinical-calculation-core.md)

## Roadmap imediato

Próximo ciclo: resolução de entidades `STAGING -> CANONICAL`, gerando `active_ingredient`, `medication_product` e `presentation` com `calculation_ready=false` até validação clínica explícita.
