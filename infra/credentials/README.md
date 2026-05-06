# Credenciais

## GCP

### Opção A — Application Default Credentials (recomendado para dev local)

```bash
gcloud auth application-default login
gcloud config set project YOUR_GCP_PROJECT_ID
```

### Opção B — Service Account (recomendado para CI/CD)

```bash
# 1. Crie a service account
gcloud iam service-accounts create paperclip-tf \
  --display-name="OpenTofu Paperclip"

# 2. Atribua as roles necessárias
gcloud projects add-iam-policy-binding YOUR_GCP_PROJECT_ID \
  --member="serviceAccount:paperclip-tf@YOUR_GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/compute.admin"

gcloud projects add-iam-policy-binding YOUR_GCP_PROJECT_ID \
  --member="serviceAccount:paperclip-tf@YOUR_GCP_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"

# 3. Crie e baixe a chave (guarde fora do repo!)
gcloud iam service-accounts keys create ./paperclip-tf-key.json \
  --iam-account="paperclip-tf@YOUR_GCP_PROJECT_ID.iam.gserviceaccount.com"

# 4. Aponte o provider para a chave
export GOOGLE_APPLICATION_CREDENTIALS="$(pwd)/paperclip-tf-key.json"
```

---

## CloudFlare API Token

1. Acesse https://dash.cloudflare.com/profile/api-tokens
2. Clique em **Create Token** → **Create Custom Token**
3. Configure as permissões:

| Permission | Resource | Access |
|---|---|---|
| Zone → DNS | seu-dominio.com | Edit |
| Account → Cloudflare Tunnel | All accounts | Edit |

4. Copie o token gerado para `terraform.tfvars`

---

## Encontrar IDs do CloudFlare

**Zone ID** (para `cloudflare_zone_id`):
- Dashboard → selecione seu domínio → Overview → barra lateral direita → "Zone ID"

**Account ID** (para `cloudflare_account_id`):
- Dashboard → a URL será `dash.cloudflare.com/<ACCOUNT_ID>/...`
- Ou: Overview de qualquer zona → barra lateral direita → "Account ID"

---

## Chave SSH

Se ainda não tem uma chave SSH:
```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
cat ~/.ssh/id_ed25519.pub   # cole em terraform.tfvars → ssh_public_key
```
