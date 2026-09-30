# Validação da incorporação nativa

Versão proposta: 1.6.0+9. Exportação Anvisa de referência: 25/09/2026.

Verificado localmente:
- Integridade SQLite: ok.
- 8.831 produtos e 85.649 registros documentais no asset embarcado.
- Comparação de todos os payloads com o catálogo coletado: igualdade integral.
- Busca textual por medicamento no SQLite: ok.
- Dart format executado nos arquivos modificados.
- Tela ProfessionalLeafletScreen sem PDF, WebView ou abertura externa.

Não validado nesta execução:
- flutter analyze e flutter test: inicialização do SDK bloqueada pela revisão automática.
- Compilação Android e testes de execução em dispositivo.
- Testes de integração PostgreSQL no CI.
- Publicação no GitHub: bloqueada pela revisão automática, aguardando autorização explícita do destino.

O código inclui teste de integração do asset real com consultas, paginação e
histórico. O workflow Android também aceita pull requests para gerar APK após
publicação autorizada. A entrega local não implica implantação na branch main.

Conteúdo clínico: os CSVs coletados não possuem texto de bula. A interface não
apresenta metadados como instruções de uso. Referências DailyMed preexistentes
são exibidas como texto nativo, mantendo fonte, idioma e aviso de vínculo por
princípio ativo.
