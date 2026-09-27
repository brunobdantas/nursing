# ADR 0001 — Calculation Core determinístico e offline

Status: Aceito

## Contexto

O aplicativo apoiará enfermeiros e técnicos de enfermagem em cálculos de administração de medicamentos. Uma saída incorreta pode produzir risco clínico.

## Decisão

O cálculo ocorrerá localmente no dispositivo, por funções puras, determinísticas, versionadas e testadas. IA generativa não executará dose. O V1 utiliza `Decimal`, não `double`, não converte unidades silenciosamente e falha fechado quando um resultado exige política de arredondamento ainda não aprovada.

## Consequências

- funcionamento offline;
- auditabilidade por fórmula e versão;
- testes clínicos obrigatórios em PR;
- necessidade de versionar futuras políticas de conversão e arredondamento.
