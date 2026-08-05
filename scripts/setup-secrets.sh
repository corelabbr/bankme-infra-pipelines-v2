#!/usr/bin/env bash
# =============================================================================
# setup-secrets.sh
#
# Cria os secrets no GCP Secret Manager para um projeto.
# Lê a lista de secrets do .github/config/environments.yml do projeto.
# Cria todos com valor "CHANGEME" — preencha os valores reais depois no Console.
#
# Uso (rodar dentro do diretório do projeto):
#   ./path/to/setup-secrets.sh --project bankme-frontend-dev
#   ./path/to/setup-secrets.sh --project bankme-frontend-dev --prefix front_bankme
#
# Ou especificando os secrets manualmente:
#   ./path/to/setup-secrets.sh --project bankme-frontend-dev \
#     --secrets "front_bankme-AUTH0_URL,front_bankme-JWT_SECRET,front_bankme-DB_URL"
#
# Pré-requisitos:
#   - gcloud CLI instalado e autenticado
#   - Secret Manager API habilitada no projeto (setup-gcp.sh já habilita)
#   - python3 instalado (para ler o environments.yml)
# =============================================================================

set -euo pipefail

PROJECT=""
PREFIX=""
CUSTOM_SECRETS=""
ENV_FILE=".github/config/environments.yml"

usage() {
  echo "Uso: $0 --project <gcp-project-id> [--prefix <prefixo>] [--secrets <lista-csv>]"
  echo ""
  echo "  --project   ID do projeto GCP (obrigatório)"
  echo "  --prefix    Prefixo dos secrets (ex: front_bankme). Se omitido, lê do environments.yml"
  echo "  --secrets   Lista de nomes de secrets separados por vírgula (ignora environments.yml)"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)  PROJECT="$2";         shift 2 ;;
    --prefix)   PREFIX="$2";          shift 2 ;;
    --secrets)  CUSTOM_SECRETS="$2";  shift 2 ;;
    *) usage ;;
  esac
done

[[ -z "$PROJECT" ]] && usage

echo ""
echo "========================================================"
echo " Setup Secrets no GCP Secret Manager"
echo " Projeto: $PROJECT"
echo "========================================================"
echo ""

# ── Coletar lista de secrets ──────────────────────────────────────────────────
declare -a SECRET_NAMES=()

if [ -n "$CUSTOM_SECRETS" ]; then
  IFS=',' read -ra SECRET_NAMES <<< "$CUSTOM_SECRETS"
elif [ -f "$ENV_FILE" ]; then
  echo "→ Lendo secrets do $ENV_FILE..."
  SECRETS_RAW=$(python3 - <<'PYEOF'
import yaml, sys

with open(".github/config/environments.yml") as f:
    config = yaml.safe_load(f)

seen = set()
for env_name, env_config in config.get("environments", {}).items():
    for secret_ref in env_config.get("runtime-secrets", {}).values():
        secret_name = secret_ref.split(":")[0]
        if secret_name not in seen:
            print(secret_name)
            seen.add(secret_name)
    for secret_ref in env_config.get("volume-secrets", {}).values():
        secret_name = secret_ref.split(":")[0]
        if secret_name not in seen:
            print(secret_name)
            seen.add(secret_name)
PYEOF
)
  while IFS= read -r line; do
    [ -n "$line" ] && SECRET_NAMES+=("$line")
  done <<< "$SECRETS_RAW"
else
  echo "ERRO: environments.yml não encontrado e --secrets não fornecido."
  echo "Execute este script dentro do diretório do projeto ou use --secrets."
  exit 1
fi

if [ ${#SECRET_NAMES[@]} -eq 0 ]; then
  echo "Nenhum secret encontrado para criar."
  exit 0
fi

echo "→ Criando ${#SECRET_NAMES[@]} secrets com valor 'CHANGEME'..."
echo ""

CREATED=0
SKIPPED=0

for SECRET in "${SECRET_NAMES[@]}"; do
  [ -z "$SECRET" ] && continue
  echo -n "  $SECRET... "
  if gcloud secrets describe "$SECRET" --project="$PROJECT" &>/dev/null; then
    echo "já existe (pulando)"
    SKIPPED=$((SKIPPED + 1))
  else
    echo -n "CHANGEME" | gcloud secrets create "$SECRET" \
      --project="$PROJECT" \
      --replication-policy=automatic \
      --data-file=- &>/dev/null
    echo "✓ criado"
    CREATED=$((CREATED + 1))
  fi
done

echo ""
echo "========================================================"
echo " Concluído: $CREATED criados, $SKIPPED já existiam"
echo ""
echo " IMPORTANTE: Preencha os valores reais em:"
echo " https://console.cloud.google.com/security/secret-manager?project=$PROJECT"
echo ""
echo " Para atualizar um secret via CLI:"
echo "   echo -n 'valor-real' | gcloud secrets versions add NOME_SECRET \\"
echo "     --project=$PROJECT --data-file=-"
echo "========================================================"
