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

hotfix/* PR mergeado em main
    └── deploy-hotfix.yml → build Docker → push AR de staging com tag hotfix-*
                                         (sem deploy automático)
    └── Senior aciona deploy-production.yml → version: hotfix-nome-do-branch
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
- [ ] Time **`seniors`** criado na organização GitHub (`github.com/orgs/bankme-tech/teams`)
  - Este time é usado pelo `validate-merge-permission` e pelo `deploy-production`
  - Sem ele, os checks de permissão vão falhar
- [ ] Projeto criado no **SonarCloud** e `sonar-project.properties` configurado (ver Passo 3b)

---

## Sobre versionamento

Os workflows dos projetos referenciam este repositório com a tag `@v1`:
```yaml
uses: bankme-tech/infra-pipelines-v2/.github/workflows/build-and-deploy.yml@v1
```

Isso significa que **atualizações no infra-pipelines só chegam aos projetos quando uma nova tag `v1`, `v2`, etc. for criada**. Para lançar uma nova versão:
```bash
git tag v1.0.1 && git push origin v1.0.1
# Para atualizar a tag flutuante v1:
git tag -f v1 && git push origin v1 --force
```

> **Atenção:** `@main` pode ser usado em desenvolvimento/testes mas **não em produção** — qualquer commit no main afetaria todos os projetos imediatamente.

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

# Para production: informe também o projeto de staging via --staging-project
# Isso permite que o SA de produção leia imagens do AR de staging (promote)
./scripts/setup-gcp.sh \
  --project         bankme-frontend-prd \
  --env             production \
  --region          us-central1 \
  --gh-org          bankme-tech \
  --gh-repo         bankme-frontend \
  --ar-repo         bankme-frontend \
  --staging-project bankme-frontend-stg
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

> **Para projetos existentes** que já usam o `bankme-tech/infra-pipelines` antigo, veja a seção [Migração de projetos existentes](#migração-de-projetos-existentes) ao final deste documento.

Dentro do repositório do projeto, copie os arquivos da pasta `templates/`:

```bash
# Dentro do repositório bankme-frontend (por exemplo)
cd /caminho/para/bankme-frontend

# Criar as pastas
mkdir -p .github/workflows .github/config

# Copiar todos os workflows template
cp /caminho/para/infra-pipelines-v2/templates/.github/workflows/*.yml .github/workflows/
cp /caminho/para/infra-pipelines-v2/templates/.github/config/environments.yml .github/config/
cp /caminho/para/infra-pipelines-v2/templates/.github/CODEOWNERS .github/CODEOWNERS
cp /caminho/para/infra-pipelines-v2/templates/sonar-project.properties sonar-project.properties
```

---

## Passo 3b — Configurar o SonarCloud

1. Acesse [sonarcloud.io](https://sonarcloud.io) e crie o projeto para o repositório
2. Edite o `sonar-project.properties` copiado:
   - `sonar.projectKey` → chave gerada pelo SonarCloud (geralmente `bankme-tech_nome-do-repo`)
   - `sonar.organization` → `bankme-tech`
3. Edite o `.github/workflows/cicd-pull-request.yml`:
   - `sonar-project-key` → mesma chave do `sonar-project.properties`

---

## Passo 3c — Revisar o CODEOWNERS

Edite `.github/CODEOWNERS` para refletir quem deve aprovar PRs no seu projeto:
```
# Exemplo: apenas seniors aprovam mudanças em arquivos de infra
.github/    @bankme-tech/seniors
Dockerfile  @bankme-tech/seniors

# Qualquer dev pode aprovar código de aplicação
src/        @bankme-tech/developers
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
git add .github/ sonar-project.properties
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
| `deploy-hotfix.yml` | PR `hotfix/*` mergeado em `main` | Build + push no AR de staging (sem deploy automático) |
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

**O promote falha com "Permission denied" ao fazer docker pull da imagem de staging**
→ O SA de produção não tem acesso de leitura no AR de staging. Execute:
```bash
gcloud projects add-iam-policy-binding SEU_PROJETO_STAGING \
  --member="serviceAccount:github-deployer@SEU_PROJETO_PROD.iam.gserviceaccount.com" \
  --role="roles/artifactregistry.reader"
```
Ou re-execute `setup-gcp.sh --env production --staging-project SEU_PROJETO_STAGING`.

---

## Migração de projetos existentes

Para projetos que já usam o `bankme-tech/infra-pipelines` antigo (com `GCP_SA_KEY`):

### O que muda

| | Antes | Depois |
|---|---|---|
| **Auth GCP** | `GCP_SA_KEY` (JSON no GitHub Secret) | WIF (sem chave) |
| **Config** | `load-env-config` action + `gcp-project-id` no YAML | Python inline + `vars.*` do GitHub |
| **App secrets** | GCP Secret Manager via `runtime-secrets` | GCP Secret Manager via `runtime-secrets` (igual) |
| **Deploy prod** | Rebuild | Promote por digest (não rebuild) |

### Passo a passo

**1. Configure o GCP com WIF** (mesmos passos do Passo 1 deste guia)
```bash
./scripts/setup-gcp.sh --project SEU_PROJETO --env develop ...
```
O WIF substitui o `GCP_SA_KEY` — mantenha o SA key como backup até validar.

**2. Configure o GitHub** (Passo 2 deste guia)
Adicione as variáveis nos environments (o secret `GCP_SA_KEY` pode coexistir — os novos workflows não o usam).

**3. Substitua os workflows**
```bash
# Dentro do repositório do projeto
cp /caminho/infra-pipelines-v2/templates/.github/workflows/*.yml .github/workflows/
cp /caminho/infra-pipelines-v2/templates/.github/CODEOWNERS .github/
cp /caminho/infra-pipelines-v2/templates/sonar-project.properties .
```

**4. Atualize o `environments.yml`**
O novo schema remove `gcp-project-id`, `gcp-region`, `gcp-registry` do YAML (vão para GitHub Variables).
Mantenha `runtime-secrets` e `volume-secrets` — são compatíveis.

**5. Crie os secrets no Secret Manager** (se ainda não existem)
```bash
./scripts/setup-secrets.sh --project SEU_PROJETO
```

**6. Faça commit e teste** — siga os Passos 7 e 8 deste guia.

**7. Após validar**, remova o `GCP_SA_KEY` do GitHub Secrets (ele não é mais necessário).

### Projetos com volume-secrets (SSL certificates)

`api-oracle`, `api-bifrost`, `api-data-warehouse` usam certificados SSL montados como arquivos.
O novo pipeline suporta isso nativamente via `volume-secrets` no `environments.yml`:
```yaml
volume-secrets:
  '/secrets/pg-ssl-ca/server-ca.pem': prefixo_projeto-PG_SSL_SERVER_CA:latest
```
Nenhuma mudança nos secrets do GCP Secret Manager é necessária — apenas o `environments.yml` precisa ser atualizado para o novo schema.
