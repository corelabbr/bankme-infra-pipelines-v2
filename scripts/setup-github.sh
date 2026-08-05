#!/usr/bin/env bash
# =============================================================================
# setup-github.sh
#
# Configura os GitHub Environments, Variables e Secrets de um repositório
# para usar o pipeline bankme-infra-pipelines-v2.
#
# Uso:
#   ./setup-github.sh --owner bankme-tech --repo bankme-frontend
#
# O script vai pedir interativamente os valores de cada ambiente.
# Pré-requisitos:
#   - gh CLI instalado e autenticado
#   - Permissão de admin no repositório GitHub
# =============================================================================

set -euo pipefail

OWNER=""
REPO=""

usage() {
  echo "Uso: $0 --owner <org-ou-user> --repo <nome-do-repo>"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --owner) OWNER="$2"; shift 2 ;;
    --repo)  REPO="$2";  shift 2 ;;
    *) usage ;;
  esac
done

[[ -z "$OWNER" || -z "$REPO" ]] && usage

FULL_REPO="$OWNER/$REPO"

echo ""
echo "========================================================"
echo " Setup GitHub para: $FULL_REPO"
echo "========================================================"

# ── Função auxiliar: criar/atualizar variável de environment ──────────────────
set_env_var() {
  local ENV="$1" NAME="$2" VALUE="$3"
  # Tenta criar; se existir, atualiza
  gh api "repos/$FULL_REPO/environments/$ENV/variables" \
    --method POST --field name="$NAME" --field value="$VALUE" --silent 2>/dev/null || \
  gh api "repos/$FULL_REPO/environments/$ENV/variables/$NAME" \
    --method PATCH --field value="$VALUE" --silent 2>/dev/null
}

# ── 1. Criar Environments ─────────────────────────────────────────────────────
echo ""
echo "→ Criando environments..."
for ENV in develop staging production; do
  gh api "repos/$FULL_REPO/environments/$ENV" --method PUT \
    --field "wait_timer=0" --silent
  echo "  ✓ $ENV"
done

# ── 2. Coletar dados por ambiente ─────────────────────────────────────────────
echo ""
echo "Preencha as variáveis GCP para cada ambiente."
echo "Você obtém esses valores ao rodar setup-gcp.sh para cada projeto/ambiente."
echo ""

for ENV in develop staging production; do
  echo "──────────────────────────────────────"
  echo " Ambiente: $ENV"
  echo "──────────────────────────────────────"

  read -rp "  GCP_PROJECT_ID: "                    GCP_PROJECT_ID
  read -rp "  GCP_REGION [us-central1]: "          GCP_REGION
  GCP_REGION="${GCP_REGION:-us-central1}"
  read -rp "  GCP_SERVICE_ACCOUNT_EMAIL: "         GCP_SA_EMAIL
  read -rp "  GCP_WORKLOAD_IDENTITY_PROVIDER: "    GCP_WIF
  read -rp "  AR_REPOSITORY: "                     AR_REPO

  set_env_var "$ENV" "GCP_PROJECT_ID"                  "$GCP_PROJECT_ID"
  set_env_var "$ENV" "GCP_REGION"                      "$GCP_REGION"
  set_env_var "$ENV" "GCP_SERVICE_ACCOUNT_EMAIL"       "$GCP_SA_EMAIL"
  set_env_var "$ENV" "GCP_WORKLOAD_IDENTITY_PROVIDER"  "$GCP_WIF"
  set_env_var "$ENV" "AR_REPOSITORY"                   "$AR_REPO"

  if [ "$ENV" = "production" ]; then
    read -rp "  GCP_STAGING_PROJECT_ID: "          GCP_STAGING_PROJECT_ID
    set_env_var "$ENV" "GCP_STAGING_PROJECT_ID"    "$GCP_STAGING_PROJECT_ID"
  fi

  echo "  ✓ Variáveis do ambiente $ENV salvas"
  echo ""
done

# ── 3. GH_PACKAGES_TOKEN (repo-level secret) ─────────────────────────────────
echo "──────────────────────────────────────"
echo " Secret: GH_PACKAGES_TOKEN"
echo " (token com permissão read:packages para instalar @bankme-tech/* do GitHub Packages)"
echo "──────────────────────────────────────"
read -rsp "  GH_PACKAGES_TOKEN: " GH_TOKEN
echo ""

gh secret set GH_PACKAGES_TOKEN \
  --repo "$FULL_REPO" \
  --body "$GH_TOKEN"
echo "  ✓ GH_PACKAGES_TOKEN salvo"

# ── 4. SONAR_TOKEN (opcional) ─────────────────────────────────────────────────
echo ""
read -rp "Deseja configurar SONAR_TOKEN? (s/N): " SETUP_SONAR
if [[ "$SETUP_SONAR" =~ ^[Ss]$ ]]; then
  read -rsp "  SONAR_TOKEN: " SONAR_TOKEN
  echo ""
  gh secret set SONAR_TOKEN \
    --repo "$FULL_REPO" \
    --body "$SONAR_TOKEN"
  echo "  ✓ SONAR_TOKEN salvo"
fi

# ── Resumo ────────────────────────────────────────────────────────────────────
echo ""
echo "========================================================"
echo " GitHub configurado para $FULL_REPO"
echo ""
echo " Próximos passos:"
echo "   1. Copie os arquivos de .github/ do diretório templates/"
echo "      para o repositório $REPO"
echo "   2. Adapte .github/config/environments.yml para o projeto"
echo "   3. Execute setup-secrets.sh para criar os secrets no GCP"
echo "   4. Preencha os valores reais dos secrets no GCP Console"
echo "   5. Execute setup-branch-protection.sh (requer GitHub Team/Enterprise)"
echo "========================================================"
