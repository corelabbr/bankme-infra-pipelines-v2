#!/usr/bin/env bash
# =============================================================================
# setup-gcp.sh
#
# Configura a infraestrutura GCP necessária para um projeto usar o pipeline.
# Deve ser executado UMA VEZ por projeto/ambiente.
#
# O que faz:
#   1. Habilita as APIs necessárias
#   2. Cria o Service Account de deploy
#   3. Concede as roles necessárias
#   4. Configura Workload Identity Federation (autenticação sem chave)
#   5. Cria o repositório no Artifact Registry
#
# Uso:
#   ./setup-gcp.sh \
#     --project   bankme-frontend-dev \
#     --env       develop \
#     --region    us-central1 \
#     --gh-org    bankme-tech \
#     --gh-repo   bankme-frontend \
#     --ar-repo   bankme-frontend
#
# Pré-requisitos:
#   - gcloud CLI instalado e autenticado (gcloud auth login)
#   - Permissão de Owner ou Editor no projeto GCP
# =============================================================================

set -euo pipefail

# ── Argumentos ───────────────────────────────────────────────────────────────
PROJECT=""
ENV=""
REGION="us-central1"
GH_ORG=""
GH_REPO=""
AR_REPO=""
SA_NAME="github-deployer"
POOL_NAME="github-pool"
PROVIDER_NAME="github-provider"

STAGING_PROJECT=""   # só necessário para --env production

usage() {
  echo "Uso: $0 --project <id> --env <develop|staging|production> --gh-org <org> --gh-repo <repo> [--region <region>] [--ar-repo <repo>] [--staging-project <id>]"
  echo ""
  echo "  --staging-project  ID do projeto GCP de staging (obrigatório quando --env production)"
  echo "                     Permite que o SA de produção leia imagens do AR de staging (promote)."
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)         PROJECT="$2";         shift 2 ;;
    --env)             ENV="$2";             shift 2 ;;
    --region)          REGION="$2";          shift 2 ;;
    --gh-org)          GH_ORG="$2";          shift 2 ;;
    --gh-repo)         GH_REPO="$2";         shift 2 ;;
    --ar-repo)         AR_REPO="$2";         shift 2 ;;
    --staging-project) STAGING_PROJECT="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -z "$PROJECT" || -z "$ENV" || -z "$GH_ORG" || -z "$GH_REPO" ]] && usage
[[ -z "$AR_REPO" ]] && AR_REPO="$GH_REPO"

SA_EMAIL="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')
WIF_PROVIDER="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/providers/${PROVIDER_NAME}"

echo ""
echo "========================================================"
echo " Setup GCP para: $GH_ORG/$GH_REPO ($ENV)"
echo " Projeto: $PROJECT | Região: $REGION"
echo "========================================================"
echo ""

# ── 1. Habilitar APIs ─────────────────────────────────────────────────────────
echo "→ Habilitando APIs..."
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project="$PROJECT" --quiet
echo "  ✓ APIs habilitadas"

# ── 2. Criar Service Account ──────────────────────────────────────────────────
echo "→ Criando Service Account $SA_EMAIL..."
if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT" &>/dev/null; then
  echo "  ✓ Service Account já existe"
else
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="GitHub Actions Deployer" \
    --project="$PROJECT"
  echo "  ✓ Service Account criado"
fi

# ── 3. Conceder roles IAM ─────────────────────────────────────────────────────
echo "→ Concedendo roles IAM..."
ROLES=(
  "roles/run.admin"
  "roles/artifactregistry.writer"
  "roles/secretmanager.secretAccessor"
  "roles/iam.serviceAccountUser"
)
for ROLE in "${ROLES[@]}"; do
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="$ROLE" \
    --quiet 2>/dev/null | grep -q "Updated" && echo "  ✓ $ROLE" || echo "  ~ $ROLE (já existia)"
done

# ── 4. Workload Identity Federation ──────────────────────────────────────────
echo "→ Configurando Workload Identity Federation..."

# Criar pool (se não existir)
if ! gcloud iam workload-identity-pools describe "$POOL_NAME" \
    --project="$PROJECT" --location=global &>/dev/null; then
  gcloud iam workload-identity-pools create "$POOL_NAME" \
    --display-name="GitHub Actions Pool" \
    --project="$PROJECT" \
    --location=global
  echo "  ✓ Pool criado: $POOL_NAME"
else
  echo "  ~ Pool já existe: $POOL_NAME"
fi

# Definir attribute condition baseado no ambiente
# staging aceita tags (deploy normal) e main (build de hotfix)
case "$ENV" in
  develop)    CONDITION="assertion.repository=='${GH_ORG}/${GH_REPO}'" ;;
  staging)    CONDITION="assertion.repository=='${GH_ORG}/${GH_REPO}' && (assertion.ref.startsWith('refs/tags/') || assertion.ref=='refs/heads/main')" ;;
  production) CONDITION="assertion.repository=='${GH_ORG}/${GH_REPO}' && assertion.ref=='refs/heads/main'" ;;
  *)          CONDITION="assertion.repository=='${GH_ORG}/${GH_REPO}'" ;;
esac

# Criar ou atualizar provider
if ! gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" \
    --workload-identity-pool="$POOL_NAME" \
    --project="$PROJECT" --location=global &>/dev/null; then
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_NAME" \
    --workload-identity-pool="$POOL_NAME" \
    --issuer-uri="https://token.actions.githubusercontent.com" \
    --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
    --attribute-condition="$CONDITION" \
    --project="$PROJECT" \
    --location=global
  echo "  ✓ Provider criado: $PROVIDER_NAME"
else
  gcloud iam workload-identity-pools providers update-oidc "$PROVIDER_NAME" \
    --workload-identity-pool="$POOL_NAME" \
    --attribute-condition="$CONDITION" \
    --project="$PROJECT" \
    --location=global
  echo "  ✓ Provider atualizado com condition para $ENV"
fi

# Vincular SA ao WIF
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_NAME}/attribute.repository/${GH_ORG}/${GH_REPO}" \
  --project="$PROJECT" --quiet 2>/dev/null
echo "  ✓ SA vinculado ao WIF"

# ── 4b. Permissão de leitura no AR de staging (só para produção) ─────────────
# O SA de produção precisa ler imagens do AR de staging para o promote funcionar.
if [ "$ENV" = "production" ]; then
  if [ -n "$STAGING_PROJECT" ]; then
    echo "→ Concedendo leitura no AR de staging ($STAGING_PROJECT)..."
    gcloud projects add-iam-policy-binding "$STAGING_PROJECT" \
      --member="serviceAccount:$SA_EMAIL" \
      --role="roles/artifactregistry.reader" \
      --quiet 2>/dev/null | grep -q "Updated" && \
      echo "  ✓ roles/artifactregistry.reader em $STAGING_PROJECT" || \
      echo "  ~ roles/artifactregistry.reader em $STAGING_PROJECT (já existia)"
  else
    echo "  ⚠ --staging-project não informado. O SA de produção não terá acesso ao AR de staging."
    echo "    Adicione manualmente depois:"
    echo "    gcloud projects add-iam-policy-binding <staging-project> \\"
    echo "      --member='serviceAccount:$SA_EMAIL' \\"
    echo "      --role='roles/artifactregistry.reader'"
  fi
fi

# ── 5. Artifact Registry ──────────────────────────────────────────────────────
echo "→ Criando Artifact Registry..."
if ! gcloud artifacts repositories describe "$AR_REPO" \
    --project="$PROJECT" --location="$REGION" &>/dev/null; then
  gcloud artifacts repositories create "$AR_REPO" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Docker images — $GH_REPO" \
    --project="$PROJECT"
  echo "  ✓ Repositório criado: $AR_REPO"
else
  echo "  ~ Repositório já existe: $AR_REPO"
fi

# ── Resumo ────────────────────────────────────────────────────────────────────
echo ""
echo "========================================================"
echo " Concluído! Adicione estas variáveis no GitHub Environment '$ENV':"
echo "========================================================"
echo ""
echo "  GCP_PROJECT_ID                = $PROJECT"
echo "  GCP_REGION                    = $REGION"
echo "  GCP_SERVICE_ACCOUNT_EMAIL     = $SA_EMAIL"
echo "  GCP_WORKLOAD_IDENTITY_PROVIDER = $WIF_PROVIDER/providers/$PROVIDER_NAME"
echo "  AR_REPOSITORY                 = $AR_REPO"
echo ""
echo "  (se ambiente production, adicionar também:)"
echo "  GCP_STAGING_PROJECT_ID        = <projeto-id-de-staging>"
echo "========================================================"
