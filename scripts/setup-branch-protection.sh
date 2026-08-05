#!/usr/bin/env bash
# =============================================================================
# setup-branch-protection.sh
#
# Configura branch protection rules e rulesets no GitHub para um repositório
# da Bankme. Requer GitHub Team/Enterprise (plano pago).
#
# Uso:
#   ./setup-branch-protection.sh <owner> <repo>
#
# Exemplos:
#   ./setup-branch-protection.sh bankme-tech bankme-frontend
#   ./setup-branch-protection.sh bankme-tech api-oracle
#
# Requisitos:
#   - gh CLI autenticado com conta que tem admin no repo
#   - GitHub Team ou Enterprise (branch protection com required checks = plano pago)
# =============================================================================

set -euo pipefail

OWNER="${1:?Uso: $0 <owner> <repo>}"
REPO="${2:?Uso: $0 <owner> <repo>}"
ORG="$OWNER"

echo "Configurando branch protection para $OWNER/$REPO..."
echo ""

# =============================================================================
# 1. BRANCH PROTECTION — main
#    - Exige PR aprovado por 1 reviewer
#    - Exige CI passando (build-and-deploy / cicd-pull-request)
#    - Bloqueia push direto (somente via PR)
#    - Somente seniors podem fazer merge
# =============================================================================
echo "→ Configurando proteção da branch main..."
gh api "repos/$OWNER/$REPO/branches/main/protection" \
  --method PUT \
  --header "Accept: application/vnd.github+json" \
  --field "required_status_checks[strict]=true" \
  --field "required_status_checks[contexts][]=CI / CI" \
  --field "enforce_admins=false" \
  --field "required_pull_request_reviews[required_approving_review_count]=1" \
  --field "required_pull_request_reviews[dismiss_stale_reviews]=true" \
  --field "required_pull_request_reviews[require_code_owner_reviews]=true" \
  --field "restrictions[users][]=" \
  --field "restrictions[teams][]=seniors" \
  --field "allow_force_pushes=false" \
  --field "allow_deletions=false" \
  --field "block_creations=false" \
  --field "required_conversation_resolution=true" \
  --silent && echo "   ✓ main protegida"

# =============================================================================
# 2. BRANCH PROTECTION — develop
#    - Exige PR aprovado
#    - Exige CI passando
#    - Bloqueia push direto
# =============================================================================
echo "→ Configurando proteção da branch develop..."
gh api "repos/$OWNER/$REPO/branches/develop/protection" \
  --method PUT \
  --header "Accept: application/vnd.github+json" \
  --field "required_status_checks[strict]=false" \
  --field "required_status_checks[contexts][]=CI / CI" \
  --field "enforce_admins=false" \
  --field "required_pull_request_reviews[required_approving_review_count]=1" \
  --field "required_pull_request_reviews[dismiss_stale_reviews]=true" \
  --field "restrictions=null" \
  --field "allow_force_pushes=false" \
  --field "allow_deletions=false" \
  --field "required_conversation_resolution=true" \
  --silent && echo "   ✓ develop protegida"

# =============================================================================
# 3. ENVIRONMENTS — proteção de deploy em produção
#    - Exige aprovação manual de reviewer do time seniors
#    - Apenas branches main e tags v* podem deployar em produção
# =============================================================================
echo "→ Configurando proteção do environment production..."
gh api "repos/$OWNER/$REPO/environments/production" \
  --method PUT \
  --header "Accept: application/vnd.github+json" \
  --field "wait_timer=0" \
  --field "reviewers[][type]=Team" \
  --field "reviewers[][id]=$(gh api "orgs/$ORG/teams/seniors" --jq '.id')" \
  --field "deployment_branch_policy[protected_branches]=false" \
  --field "deployment_branch_policy[custom_branch_policies]=true" \
  --silent && echo "   ✓ environment production configurado"

# Branch/tag policy para production: apenas main e tags v*
gh api "repos/$OWNER/$REPO/environments/production/deployment-branch-policies" \
  --method POST \
  --field "name=main" \
  --field "type=branch" \
  --silent 2>/dev/null || true

gh api "repos/$OWNER/$REPO/environments/production/deployment-branch-policies" \
  --method POST \
  --field "name=v*" \
  --field "type=tag" \
  --silent 2>/dev/null || true

echo "   ✓ deployment policy: main + tags v*"

# =============================================================================
# 4. ENVIRONMENTS — staging
#    - Apenas releases (tags) podem deployar
# =============================================================================
echo "→ Configurando proteção do environment staging..."
gh api "repos/$OWNER/$REPO/environments/staging" \
  --method PUT \
  --header "Accept: application/vnd.github+json" \
  --field "wait_timer=0" \
  --field "deployment_branch_policy[protected_branches]=false" \
  --field "deployment_branch_policy[custom_branch_policies]=true" \
  --silent && echo "   ✓ environment staging configurado"

gh api "repos/$OWNER/$REPO/environments/staging/deployment-branch-policies" \
  --method POST \
  --field "name=v*" \
  --field "type=tag" \
  --silent 2>/dev/null || true

echo "   ✓ deployment policy: apenas tags v*"

# =============================================================================
# 5. ENVIRONMENTS — develop
#    - Apenas branch develop pode deployar
# =============================================================================
echo "→ Configurando proteção do environment develop..."
gh api "repos/$OWNER/$REPO/environments/develop" \
  --method PUT \
  --header "Accept: application/vnd.github+json" \
  --field "wait_timer=0" \
  --field "deployment_branch_policy[protected_branches]=false" \
  --field "deployment_branch_policy[custom_branch_policies]=true" \
  --silent && echo "   ✓ environment develop configurado"

gh api "repos/$OWNER/$REPO/environments/develop/deployment-branch-policies" \
  --method POST \
  --field "name=develop" \
  --field "type=branch" \
  --silent 2>/dev/null || true

echo "   ✓ deployment policy: apenas branch develop"

# =============================================================================
# 6. CODEOWNERS — garantir que o arquivo existe
#    (o arquivo .github/CODEOWNERS já deve existir no repo)
# =============================================================================
echo "→ Verificando CODEOWNERS..."
if gh api "repos/$OWNER/$REPO/contents/.github/CODEOWNERS" --silent 2>/dev/null; then
  echo "   ✓ CODEOWNERS presente"
else
  echo "   ⚠ CODEOWNERS não encontrado — crie .github/CODEOWNERS antes de rodar este script"
fi

# =============================================================================
# RESUMO
# =============================================================================
echo ""
echo "============================================================"
echo " Branch protection configurado para $OWNER/$REPO"
echo "============================================================"
echo ""
echo " main:"
echo "   • Push direto bloqueado"
echo "   • PR obrigatório com 1 aprovação"
echo "   • CI (cicd-pull-request) deve passar"
echo "   • Merge restrito ao time @$ORG/seniors"
echo "   • Code owner review obrigatório"
echo ""
echo " develop:"
echo "   • Push direto bloqueado"
echo "   • PR obrigatório com 1 aprovação"
echo "   • CI deve passar"
echo ""
echo " Environments:"
echo "   • develop  → apenas branch develop"
echo "   • staging  → apenas tags v*"
echo "   • production → main + tags v* + aprovação do time seniors"
echo ""
echo " Próximos passos manuais:"
echo "   1. Verificar se o team ID do 'seniors' foi resolvido corretamente"
echo "   2. Ajustar 'required_status_checks[contexts]' se os nomes dos"
echo "      checks mudarem (ex: 'CI / CI' → 'Pull Request CI / CI')"
echo "   3. Ativar 'Require deployments to succeed' nas configurações"
echo "      do repositório se quiser bloquear merge até o deploy passar"
echo "============================================================"
