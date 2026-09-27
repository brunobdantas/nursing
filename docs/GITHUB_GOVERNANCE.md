# Governança GitHub

## Branch principal

`main`

## Checks obrigatórios recomendados

- `clinical-core-tests`
- `backend-tests`

Configurar no Ruleset da `main`:

- Require a pull request before merging;
- Require status checks to pass;
- Require branch to be up to date;
- Do not allow bypass para alterações de código clínico.

## Automação

- GitHub Actions: testes mobile clínicos e backend/Alembic;
- Dependabot: Python, Dart/Flutter e GitHub Actions;
- CODEOWNERS: revisão do proprietário;
- PR template: checklist explícito de impacto clínico.

## GitHub Project sugerido

Colunas/campos: Backlog, Ready, In Progress, Clinical Review, Tech Review, Done.

Labels mínimas: `backend`, `mobile`, `data`, `clinical-safety`, `bug`, `enhancement`, `dependencies`, `ci`.
