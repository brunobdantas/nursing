#!/usr/bin/env bash
set -euo pipefail
OWNER="${1:?Uso: scripts/publish_github.sh <owner> [repo] [private|public]}"
REPO="${2:-nursing}"
VISIBILITY="${3:-private}"
if ! command -v gh >/dev/null 2>&1; then echo "GitHub CLI (gh) não encontrado." >&2; exit 1; fi
if ! gh auth status >/dev/null 2>&1; then echo "GitHub CLI não autenticado. Execute: gh auth login" >&2; exit 1; fi
case "$VISIBILITY" in private|public) ;; *) echo "Visibilidade deve ser private ou public." >&2; exit 1 ;; esac
if gh repo view "$OWNER/$REPO" >/dev/null 2>&1; then
  echo "Repositório $OWNER/$REPO já existe; configurando remote origin."
  git remote remove origin >/dev/null 2>&1 || true
  git remote add origin "https://github.com/$OWNER/$REPO.git"
  git push -u origin main
else
  gh repo create "$OWNER/$REPO" "--$VISIBILITY" --source=. --remote=origin --push --description "Bulário inteligente e Calculation Core seguro para enfermagem"
fi
