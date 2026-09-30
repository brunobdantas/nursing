# Coleta do Bulário Anvisa

Implementação: `backend/scripts/etl_bulario.py`. Integrada ao publicador de base
clínica existente, inclusive sua execução semanal. Pode ser executada localmente:

```bash
cd backend
python scripts/etl_bulario.py
```

Com `DATABASE_URL`, grava nas tabelas já existentes `raw.source_system`,
`raw.source_snapshot` e `staging.source_assertion`. Sem essa variável, gera o
catálogo SQLite e o relatório, sem precisar de PostgreSQL. Para reprocessar os
arquivos oficiais já baixados:

```bash
python scripts/etl_bulario.py --product-csv produto.csv --document-csv documento.csv
```

## Cobertura e limites

São coletadas todas as linhas, sem filtro de medicamento ou limitação de páginas,
dos arquivos oficiais:

- https://dados.anvisa.gov.br/dados/CONSULTAS/DOCUMENTOS/TA_CONSULTA_BULA_PRODUTO.CSV
- https://dados.anvisa.gov.br/dados/CONSULTAS/DOCUMENTOS/TA_CONSULTA_BULA_DOCUMENTO.CSV

Esses arquivos são **metadados**, não PDFs nem texto integral de bula. Não há
garantia de equivalência integral com a consulta web. Em 28/09/2026, o portal de
consulta bloqueou o navegador de inspeção pelo Cloudflare. Não foi contornado.
Esta entrega não baixa os PDFs, não extrai seu texto e não disponibiliza bulas
brasileiras integrais no aplicativo. O relatório indica expressamente essa pendência.
O carregamento DailyMed existente permanece independente.

O layout observado é sem cabeçalho, com 12 colunas de produto e 10 de documento.
São preservados todos os valores originais em `raw_columns`; campos ainda sem
semântica confirmada ficam posicionais. Números de registro, processo e CNPJ são
texto. Um documento é relacionado a um produto somente pela combinação exata
de processo e identificador do documento; correspondência por nome não é usada.
Não se infere que um registro documental seja bula vigente, profissional ou do
paciente a partir do nome do medicamento ou de sua situação administrativa.

## Operação

Saída padrão: `backend/data/raw/bulario/`:

- `raw/<sha256>/<arquivo>.CSV`: cópias originais imutáveis por hash.
- `bulario.sqlite`: geração completa com índices de registro, processo e documento.
- `summary.json`: contagens, hashes, vínculos exatos, pendências e horário da coleta.

Downloads têm timeout e tentativas limitadas para falhas transitórias. 401/403
interrompem a coleta, sem tentar contornar controles. Esquema inválido, HTML ou
arquivo vazio interrompem antes da publicação. PostgreSQL usa transação única,
lock da rotina e deduplicação por hash do snapshot. Reexecutar retoma a partir dos
snapshots já importados; arquivos não são baixados em paralelo. SQLite é trocado
atomicamente após validação das duas fontes. A versão anterior é preservada em
caso de falha de validação. Não executar dois processos no mesmo diretório de saída.

Os artefatos de coleta são preservados por 30 dias no GitHub Actions. O banco
temporário do publicador não é um banco de produção: os registros de staging não
entram automaticamente no pacote clínico offline. Em servidor persistente, definir
`DATABASE_URL` e manter o diretório RAW com backup.

## Próxima etapa bloqueada

Para concluir as bulas integrais, é necessário um meio autorizado e funcional de
obter os PDFs oficiais e identificar produto, versão e tipo de bula. Esse adaptador
deve validar PDF, preservar o original e seu hash, registrar falhas individualmente
e revisar a extração antes de promover conteúdo para `curated.professional_leaflet`.
Não transformar texto extraído automaticamente em regras de dose ou administração.

## Aplicativo 1.6.0

O catálogo completo foi incorporado ao asset `catalogue-v1.sqlite.gz`, gerado
por `scripts/build_bulario_mobile.py`. É descompactado em segundo plano na primeira
abertura e consultado localmente, com paginação. Produtos e todos os documentos
são acessíveis pelo módulo Bulário Anvisa na página inicial e na busca global.
As fichas têm abas Principal, Histórico, Fonte e Notas, além de favoritos locais.
Todas as colunas da exportação são consultáveis; campos de significado não
confirmado são identificados pelo número da coluna.

A tela de referências clínicas agora usa somente texto nativo. A implementação
anterior de PDF/WebView foi removida. A base DailyMed já existente mantém sua
identificação de fonte, idioma e vínculo por princípio ativo. Não houve tradução
automática nem criação de texto de bula Anvisa. Os dados de catálogo não são
convertidos em posologia.

Para atualizar o pacote embarcado, executar o ETL, depois o construtor do asset,
atualizar o nome versionado do arquivo em pubspec e no repositório Dart e gerar
novo APK. Essa base embarcada é independente da sincronização clínica existente.
Favoritos e notas de produtos usam identidade composta por produto, processo e
registro. Mudanças de ordem dos registros não alteram essas identidades.
