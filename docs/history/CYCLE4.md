# Ciclo 4 — PostgreSQL, Alembic, ETL ANVISA e testes da API

Este pacote materializa as camadas RAW -> STAGING -> CANONICAL -> CURATED no PostgreSQL,
introduz a primeira migration Alembic, implementa a ingestão do dataset aberto de
medicamentos da ANVISA e adiciona testes de integração do contrato FastAPI.

## Estrutura

```text
nursing_mvp_cycle4/
├── docker-compose.yml
├── README_CYCLE4.md
└── backend/
    ├── .env.example
    ├── alembic.ini
    ├── alembic/
    │   ├── env.py
    │   ├── script.py.mako
    │   └── versions/
    │       └── 001_initial_schema.py
    ├── app/
    │   ├── api/
    │   │   ├── router.py
    │   │   └── schemas.py
    │   └── db/
    │       └── models.py
    ├── scripts/
    │   └── etl_anvisa.py
    ├── tests/
    │   └── test_api.py
    ├── pytest.ini
    ├── requirements.txt
    └── schema_preview.sql
```

## 1. Subir PostgreSQL 18

Na raiz do pacote:

```bash
docker compose up -d postgres
```

## 2. Instalar dependências

```bash
cd backend
python -m venv .venv
source .venv/bin/activate  # Windows PowerShell: .venv\\Scripts\\Activate.ps1
pip install -r requirements.txt
```

Defina a conexão:

```bash
export DATABASE_URL='postgresql+asyncpg://nursing_app:nursing_app_local@localhost:5432/nursing_mvp'
```

PowerShell:

```powershell
$env:DATABASE_URL='postgresql+asyncpg://nursing_app:nursing_app_local@localhost:5432/nursing_mvp'
```

## 3. Aplicar migration

```bash
alembic -c alembic.ini upgrade head
```

A migration cria:

- extensão `pg_trgm`;
- schemas `raw`, `staging`, `canonical`, `curated`;
- 13 tabelas do modelo;
- índices B-tree e GIN/trigram;
- FKs, checks e unique constraints do ORM.

`schema_preview.sql` foi gerado com `alembic upgrade head --sql` e serve apenas como
artefato de conferência; a fonte de verdade é a migration Python.

## 4. Executar ETL ANVISA

```bash
python scripts/etl_anvisa.py
```

Por padrão o pipeline baixa:

```text
https://dados.anvisa.gov.br/dados/DADOS_ABERTOS_MEDICAMENTOS.csv
```

O fluxo é:

```text
HTTP download
  -> SHA-256
  -> cópia RAW imutável local
  -> raw.source_system (ANVISA)
  -> raw.source_snapshot
  -> validação mínima do schema do CSV
  -> staging.source_assertion (1 assertion por linha da fonte)
```

Cada assertion guarda:

- `entity_key` com identificadores disponíveis;
- `value_json.raw` com a linha original;
- `value_json.normalized` com headers normalizados e valores tratados;
- `source_locator` com dataset, URL e número da linha;
- `content_hash` por registro.

O pipeline **não promove dados para CANONICAL nem CURATED**. Essa separação é deliberada:
STAGING registra o que a fonte afirmou; uma etapa posterior fará entity resolution,
normalização clínica e criação de `field_provenance`.

### Reprocessamento local / replay

```bash
python scripts/etl_anvisa.py --csv-path /caminho/DADOS_ABERTOS_MEDICAMENTOS.csv
```

### Idempotência

A chave de idempotência é:

```text
(source_system_id, checksum_sha256)
```

Se o mesmo arquivo for ingerido novamente, nenhum novo snapshot/assertion é criado.

## 5. Testes da API

```bash
pytest -q
```

Casos cobertos:

1. `/v1/medications/search` retorna princípios ativos e medicamentos no contrato esperado;
2. `/v1/medications/{id}` retorna concentração estruturada e `calculation_ready`;
3. `calculation_ready=true` sem concentração completa bloqueia a resposta com HTTP 503 e
   código `CLINICAL_DATA_INTEGRITY_ERROR`.

## Decisões de safety-by-design do Ciclo 4

- ingestão RAW/STAGING nunca torna apresentação `calculation_ready`;
- mudança inesperada no schema mínimo da ANVISA aborta a ingestão;
- arquivo original é preservado antes do parsing;
- snapshot é identificado por SHA-256;
- linha original e linha normalizada coexistem no JSON de STAGING;
- dados clínicos inconsistentes são bloqueados pela API, não mascarados;
- migration foi validada em geração SQL offline contra o metadata SQLAlchemy.
