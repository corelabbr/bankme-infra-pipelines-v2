# Bankme Infra Pipelines v2 — Guia de Onboarding

Este guia explica como conectar um novo repositório ao pipeline centralizado da Bankme.
O pipeline usa **Workload Identity Federation** (sem chaves de serviço), **GCP Secret Manager** para secrets sensíveis, e **GitHub Actions** para CI/CD.

**Projeto de referência:** `bankme-tech/bankme-frontend` — já configurado e funcional. Use como exemplo.

---

## Visão Geral do Fluxo

```
Feature PR aberto
    └── cicd-pull-request.yml
        ├── validate-permission (bloqueia merge se não for do time)
        ├── typecheck / lint / test / build / audit
        └── SonarCloud

PR mergeado em develop
    └── deploy-develop.yml → build Docker → push AR → deploy Cloud Run (develop)

GitHub Release publicada (ex: v1.2.0)
    └── deploy-staging.yml → build Docker → push AR → deploy Cloud Run (staging)

Senior aciona deploy-production.yml (manual)
    └── busca digest de staging → copia para AR de produção → deploy Cloud Run (prod)

Senior aciona manage-traffic.yml (opcional)
    └── canary X% → release-100% → ou rollback para revisão anterior
```

---

## Pré-requisitos

Antes de começar, confirme que você tem:

- [ ] `gcloud` CLI instalado ([instalar](https://cloud.google.com/sdk/docs/install))
- [ ] `gh` CLI instalado ([instalar](https://cli.github.com/))
- [ ] Autenticado em ambos: `gcloud auth login` e `gh auth login`
- [ ] Acesso de **Owner/Editor** nos projetos GCP (develop, staging, production)
- [ ] Acesso de **Admin** no repositório GitHub
- [ ] Três projetos GCP criados (um por ambiente)
- [ ] `python3` instalado (para os scripts lerem o `environments.yml`)

---

## Passo 1 — Configurar o GCP (por ambiente)

Execute o script **uma vez para cada ambiente** (develop, staging, production).

```bash
# Clonar o infra-pipelines para ter acesso aos scripts
git clone https://github.com/bankme-tech/infra-pipelines-v2.git
cd infra-pipelines-v2

chmod +x scripts/*.sh

# Exemplo: configurar o ambiente develop
./scripts/setup-gcp.sh \
  --project   bankme-frontend-dev \
  --env       develop \
  --region    us-central1 \
  --gh-org    bankme-tech \
  --gh-repo   bankme-frontend \
  --ar-repo   bankme-frontend

# Repetir para staging
./scripts/setup-gcp.sh \
  --project   bankme-frontend-stg \
  --env       staging \
  --region    us-central1 \
  --gh-org    bankme-tech \
  --gh-repo   bankme-frontend \
  --ar-repo   bankme-frontend

# Repetir para production
./scripts/setup-gcp.sh \
  --project   bankme-frontend-prd \
  --env       production \
  --region    us-central1 \
  --gh-org    bankme-tech \
  --gh-repo   bankme-frontend \
  --ar-repo   bankme-frontend
```

Ao final de cada execução, o script imprime os valores que você usará no Passo 2.

---

## Passo 2 — Configurar o GitHub

Execute o script de configuração do repositório GitHub.
Ele vai pedir interativamente os valores de cada ambiente (use os valores impressos pelo `setup-gcp.sh`):

```bash
./scripts/setup-github.sh \
  --owner bankme-tech \
  --repo  bankme-frontend
```

O script cria:
- GitHub Environments: `develop`, `staging`, `production`
- Variáveis por ambiente: `GCP_PROJECT_ID`, `GCP_REGION`, `GCP_SERVICE_ACCOUNT_EMAIL`, `GCP_WORKLOAD_IDENTITY_PROVIDER`, `AR_REPOSITORY`
- Secret de repositório: `GH_PACKAGES_TOKEN`

> **Para produção**, informe também `GCP_STAGING_PROJECT_ID` quando pedido
> (é o project ID do ambiente de staging, usado para copiar a imagem no promote).

---

## Passo 3 — Copiar os arquivos de workflow para o repositório

Dentro do repositório do projeto, copie os arquivos da pasta `templates/`:

```bash
# Dentro do repositório bankme-frontend (por exemplo)
cd /caminho/para/bankme-frontend

# Criar as pastas
mkdir -p .github/workflows .github/config

# Copiar todos os workflows template
cp /caminho/para/infra-pipelines-v2/templates/.github/workflows/*.yml .github/workflows/
cp /caminho/para/infra-pipelines-v2/templates/.github/config/environments.yml .github/config/
```

---

## Passo 4 — Adaptar o environments.yml

Edite `.github/config/environments.yml` do seu projeto:

1. **Substitua `NOME_DO_PROJETO`** pelo nome real do serviço
2. **Ajuste `resources`** (memória, CPU, instâncias) conforme necessidade
3. **Preencha `runtime-env`** com as variáveis não-sensíveis de cada ambiente
4. **Configure `runtime-secrets`** apontando para os secrets do GCP Secret Manager

Formato dos secrets:
```yaml
runtime-secrets:
  AUTH0_SECRET: meu_projeto-AUTH0_SECRET:latest
  DATABASE_URL: meu_projeto-DATABASE_URL:latest
```

> **APIs que usam SSL certificates** (PostgreSQL com SSL): use também `volume-secrets`:
> ```yaml
> volume-secrets:
>   '/secrets/pg-ssl-ca/server-ca.pem': meu_projeto-PG_SSL_SERVER_CA:latest
> ```

---

## Passo 5 — Ajustar os workflows copiados

Em cada arquivo de workflow copiado, revise:

**`cicd-pull-request.yml`:**
- `node-version`: versão do Node.js do projeto
- `sonar-project-key`: chave do projeto no SonarCloud (ex: `bankme-tech_bankme-frontend`)
- `using-prisma: true` se o projeto usa Prisma

**`deploy-production.yml`:**
- `org` e `team`: o time GitHub que pode fazer deploy em produção

---

## Passo 6 — Criar os secrets no GCP Secret Manager

Execute dentro do diretório do projeto:

```bash
# Para cada projeto GCP (develop, staging, production)
/caminho/para/infra-pipelines-v2/scripts/setup-secrets.sh \
  --project bankme-frontend-dev

/caminho/para/infra-pipelines-v2/scripts/setup-secrets.sh \
  --project bankme-frontend-stg

/caminho/para/infra-pipelines-v2/scripts/setup-secrets.sh \
  --project bankme-frontend-prd
```

O script lê automaticamente o `runtime-secrets` do `environments.yml` e cria todos os secrets com valor `CHANGEME`.

**Depois, preencha os valores reais** em:
- https://console.cloud.google.com/security/secret-manager?project=bankme-frontend-dev
- https://console.cloud.google.com/security/secret-manager?project=bankme-frontend-stg
- https://console.cloud.google.com/security/secret-manager?project=bankme-frontend-prd

Ou via CLI:
```bash
echo -n "valor-real" | gcloud secrets versions add NOME_SECRET \
  --project=bankme-frontend-dev \
  --data-file=-
```

---

## Passo 7 — Fazer o primeiro commit

```bash
git add .github/
git commit -m "feat: configure pipeline bankme-infra-pipelines-v2"
git push origin main
```

---

## Passo 8 — Testar o pipeline

**1. Teste o CI** — abra um Pull Request. Deve aparecer:
   - `validate-permission` — check de permissão
   - `ci / CI` — typecheck, lint, test, build, audit
   - `ci / SonarCloud Analysis`

**2. Teste o deploy develop** — faça um push na branch `develop` ou dispare manualmente:
   ```
   GitHub Actions → Deploy to Develop → Run workflow
   ```

**3. Teste o deploy staging** — crie uma GitHub Release com tag `v0.0.1`:
   ```
   GitHub → Releases → Draft a new release → Tag: v0.0.1 → Publish release
   ```

**4. Teste o promote para produção** — dispare manualmente:
   ```
   GitHub Actions → Deploy to Production → Run workflow
   version: v0.0.1
   reason: "Teste inicial do pipeline"
   ```

---

## Passo 9 — Configurar branch protection (requer GitHub Team ou Enterprise)

Após validar que o pipeline funciona, ative as proteções de branch:

```bash
/caminho/para/infra-pipelines-v2/scripts/setup-branch-protection.sh \
  bankme-tech bankme-frontend
```

Isso configura:
- `main`: PR obrigatório + CI deve passar + merge restrito ao time `seniors`
- `develop`: PR obrigatório + CI deve passar
- `production`: só deploya de `main` ou tags `v*` + aprovação manual do time `seniors`
- `staging`: só deploya de tags `v*`

---

## Referência rápida — workflows disponíveis

| Workflow | Gatilho | O que faz |
|---|---|---|
| `cicd-pull-request.yml` | PR aberto/atualizado | Typecheck, lint, test, build, sonar, validação de permissão |
| `deploy-develop.yml` | Push em `develop` ou manual | Build + deploy em develop |
| `deploy-staging.yml` | GitHub Release publicada | Build + deploy em staging |
| `deploy-production.yml` | Manual (seniors only) | Promote da imagem de staging para produção |
| `deploy-manual.yml` | Manual | Build + deploy em develop ou staging |
| `manage-traffic.yml` | Manual | Canary, release-100%, rollback |
| `sync-main-to-develop.yml` | Push em `main` | Backmerge automático main → develop |
| `cleanup-pr-caches.yml` | PR fechado | Limpa caches de build do GHA |

---

## Referência rápida — variáveis e secrets necessários

### GitHub Environment Variables (por ambiente)
| Variable | Descrição |
|---|---|
| `GCP_PROJECT_ID` | ID do projeto GCP |
| `GCP_REGION` | Região (ex: `us-central1`) |
| `GCP_SERVICE_ACCOUNT_EMAIL` | SA do deployer |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Resource name do WIF provider |
| `AR_REPOSITORY` | Nome do repositório no Artifact Registry |
| `GCP_STAGING_PROJECT_ID` | (só produção) ID do projeto de staging |

### GitHub Repository Secrets
| Secret | Descrição |
|---|---|
| `GH_PACKAGES_TOKEN` | Token com `read:packages` para instalar `@bankme-tech/*` |
| `SONAR_TOKEN` | Token do SonarCloud (opcional) |

---

## Dúvidas frequentes

**O deploy falha com "Permission denied on secret"**
→ O service account não tem a role `Secret Manager Secret Accessor`.
Execute:
```bash
gcloud projects add-iam-policy-binding SEU_PROJETO \
  --member="serviceAccount:github-deployer@SEU_PROJETO.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

**O deploy falha com "ALREADY_EXISTS: Revision ... already exists"**
→ Uma revisão anterior falhou e ficou com o mesmo nome. Delete o serviço e reimplante.

**O WIF falha com "rejected by the attribute condition"**
→ O atributo `ref` ou `repository` não bate com a condition do provider.
Verifique com:
```bash
gcloud iam workload-identity-pools providers describe github-provider \
  --workload-identity-pool=github-pool \
  --project=SEU_PROJETO \
  --location=global \
  --format="value(attributeCondition)"
```

**O validate-permission falha mas o CI passa**
→ Comportamento esperado se o autor do PR não está no time `seniors`.
O merge só será bloqueado depois de configurar branch protection (Passo 9).
