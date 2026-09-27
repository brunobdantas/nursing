# PRD — MVP Nursing

## Objetivo

Ferramenta mobile para enfermeiros e técnicos de enfermagem, focada em quatro jornadas: **encontrar, confirmar, administrar e calcular**.

## 1. Encontrar

### Busca

Estados obrigatórios:

- vazio: recentes ou orientação para buscar por princípio ativo/nome comercial;
- digitando: resultados separados por princípio ativo e nome comercial;
- erro de digitação: correspondência aproximada explicitamente marcada, sem seleção automática;
- LASA/Tall Man: nomes semelhantes destacados por regra validada de conteúdo, nunca por uppercase automático;
- sem resultado: nenhum medicamento é selecionado por aproximação.

Ranking: exato -> prefixo -> contains -> aliases -> aproximado.

## 2. Confirmar

A ficha deve apresentar acima da dobra, nesta ordem:

1. nome/princípio ativo;
2. apresentação e concentração;
3. forma farmacêutica;
4. via;
5. alertas críticos;
6. ações `CALCULAR` e `ADMINISTRAR`.

Troca de apresentação ou concentração invalida qualquer resultado anterior.

## 3. Administrar

A visão operacional deve priorizar via, preparação, reconstituição/diluição, tempo, incompatibilidades e cuidados de enfermagem. Ausência de dado nunca é apresentada como ausência de risco.

## 4. Calcular

A calculadora contextual recebe a apresentação validada e exige `calculation_ready=true`.

A saída mostra:

- resultado com unidade;
- memória de cálculo sempre aberta;
- cancelamento dimensional;
- fórmula e versão;
- fonte/base clínica.

Alteração de input invalida imediatamente o resultado anterior.

## Safety acceptance criteria

- busca fuzzy nunca seleciona medicamento;
- LASA tem diferenciação explícita;
- cálculo automático exige `calculation_ready=true`;
- saída sempre tem unidade;
- `0,5` em vez de `,5`;
- `5` em vez de `5,0` quando o decimal não agrega informação;
- memória de cálculo obrigatória;
- nenhum valor informado na calculadora vai para log/analytics;
- funcionamento offline para cálculo;
- ausência de dado != ausência de risco.
