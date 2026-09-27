# Arquitetura

## Visão

```text
ANVISA / DailyMed / openFDA
          |
          v
 RAW -> STAGING -> CANONICAL -> CURATED
          |                       |
          |                       v
          +-------------------- Proveniência
                                  |
                                  v
                              FastAPI
                                  |
                                  v
                           Flutter offline
                                  |
                                  v
                         Calculation Core
```

## Camadas de dados

- **RAW:** registra fonte e snapshot imutável do arquivo recebido.
- **STAGING:** registra afirmações extraídas da fonte, preservando linha original e normalização técnica.
- **CANONICAL:** representa entidades normalizadas do domínio: princípio ativo, produto, apresentação, forma e via.
- **CURATED:** contém informação operacional submetida a governança clínica, como administração e reconstituição.

## Proveniência

`field_provenance` liga um atributo canônico/curado a uma `source_assertion`, que por sua vez aponta para `source_snapshot` e `source_system`.

## Safety gates

- `calculation_ready` inicia `false`.
- API falha fechado para inconsistência entre `calculation_ready=true` e concentração estruturada incompleta.
- Calculation Core não faz conversões implícitas.
- Resultado de cálculo sempre inclui unidade, memória e versão da fórmula.
