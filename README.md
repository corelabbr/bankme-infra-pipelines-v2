# Bankme Infra Pipelines v2

Pipeline de CI/CD centralizado para todos os projetos da Bankme.
Um repositório governa o fluxo de build, deploy e operação de todos os serviços.

---

## O problema que resolve

| Antes | Depois |
|---|---|
| Cada projeto com pipeline diferente | Um pipeline padrão para todos |
| `GCP_SA_KEY` no GitHub (chave que vence, que vaza) | WIF — autenticação sem nenhuma chave |
| Secrets de app no GitHub | GCP Secret Manager (secrets nunca saem do GCP) |
| Deploy reconstrói a imagem para produção | Promote — a imagem exata de staging vai para produção |
| Rollback manual e arriscado | Rollback em 1 clique com revisão específica |
| Nenhum controle de quem faz deploy em produção | Gate de permissão — só o time `seniors` promove |

---

## Como funciona

```
Feature branch → PR aberto
    └── CI: typecheck, lint, test, build, audit, SonarCloud
        └── Permissão de merge verificada automaticamente

PR mergeado em develop
    └── Build Docker → push Artifact Registry → deploy Cloud Run (develop)

GitHub Release publicada (ex: v1.2.0)
    └── Build Docker → push Artifact Registry → deploy Cloud Run (staging)

Senior aciona deploy manual
    └── Copia imagem de staging para produção (promote, não rebuild)
        └── Canary opcional: 10% → 50% → 100% do tráfego
            └── Rollback imediato se necessário
```

---

## O que está neste repositório

```
├── .github/workflows/       ← 8 workflows reutilizáveis (o pipeline em si)
│   ├── build-and-deploy.yml      build + push + deploy
│   ├── build-and-push.yml        build + push (sem deploy — hotfix)
│   ├── cicd-pull-request.yml     CI de PR
│   ├── deploy-production.yml     promote staging → produção
│   ├── manage-traffic.yml        canary + rollback
│   ├── cleanup-artifact-registry.yml  limpeza semanal automática
│   ├── git-backmerge.yml         sync entre branches
│   └── validate-merge-permission.yml  controle de acesso
│
├── scripts/                 ← Setup automatizado
│   ├── setup-gcp.sh              configura GCP: WIF, SA, AR, APIs
│   ├── setup-github.sh           configura GitHub: environments, variables, secrets
│   ├── setup-secrets.sh          cria secrets no GCP Secret Manager
│   └── setup-branch-protection.sh  branch protection (requer plano pago)
│
├── templates/               ← Arquivos prontos para copiar em cada projeto
│   └── .github/
│       ├── workflows/            9 workflows para o projeto
│       ├── CODEOWNERS            quem aprova PRs
│       └── config/environments.yml  config por ambiente
│
└── ONBOARDING.md            ← Guia completo passo a passo
```

---

## Adotar em um novo projeto

**Tempo estimado: ~2 horas por projeto**

```bash
# 1. Configurar GCP (uma vez por ambiente: develop, staging, production)
./scripts/setup-gcp.sh --project MEU_PROJETO --env develop --gh-org bankme-tech --gh-repo MEU_REPO

# 2. Configurar GitHub (environments, variables, secrets)
./scripts/setup-github.sh --owner bankme-tech --repo MEU_REPO

# 3. Copiar os templates para o projeto
cp templates/.github/workflows/*.yml MEU_REPO/.github/workflows/
cp templates/.github/CODEOWNERS MEU_REPO/.github/
cp templates/sonar-project.properties MEU_REPO/

# 4. Criar secrets no GCP Secret Manager (com valor CHANGEME — preencher depois)
./scripts/setup-secrets.sh --project MEU_PROJETO
```

Siga o **[ONBOARDING.md](./ONBOARDING.md)** para o guia completo.

---

## Projeto de referência

**`corelabbr/bankme-frontend`** — já configurado e funcional. Use como exemplo de como ficam os workflows e o `environments.yml` após a adoção.

---

## Versão atual: `v1`

Os projetos referenciam este repo com `@v1`. Para distribuir uma atualização para todos:
```bash
git tag -f v1 && git push origin v1 --force
```
