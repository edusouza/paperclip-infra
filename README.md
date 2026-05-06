# Paperclip — Infraestrutura GCP + CloudFlare

Deploy do [Paperclip](https://paperclip.ing) numa VM GCE com Cloudflare Tunnel, provisionado via OpenTofu.

## Arquitetura

```
                        ┌─────────────────────────────────────┐
                        │         GCE VM (us-central1-a)       │
                        │         e2-standard-2 / Ubuntu 22.04 │
                        │                                       │
 Usuário                │  ┌────────────┐   ┌───────────────┐  │
    │                   │  │ cloudflared│→→→│  paperclip    │  │
    │ HTTPS             │  │  (tunnel)  │   │  :3100        │  │
    ▼                   │  └────────────┘   └───────┬───────┘  │
 CloudFlare Edge        │                           │          │
 paperclip.example.com                  ┌───────▼───────┐  │
    │                   │                  │  PostgreSQL   │  │
    │ Tunnel (mTLS)     │                  │  :5432        │  │
    └───────────────────┘                  └───────────────┘  │
                        └─────────────────────────────────────┘
```

**Por que Cloudflare Tunnel?**
- Nenhuma porta 80/443 aberta na VM — o tunnel conecta de dentro para fora
- TLS gerenciado automaticamente pelo CloudFlare (sem Certbot/Let's Encrypt)
- DDoS protection e CDN inclusos
- O IP real da VM fica oculto

---

## Pré-requisitos

| Ferramenta | Versão | Instalação |
|---|---|---|
| OpenTofu | >= 1.6 | `winget install OpenTofu.OpenTofu` |
| gcloud CLI | qualquer | [cloud.google.com/sdk](https://cloud.google.com/sdk/docs/install) |
| SSH key pair | — | `ssh-keygen -t ed25519` |

### APIs do GCP necessárias

Antes do primeiro `tofu apply`, ative as APIs abaixo no projeto `YOUR_GCP_PROJECT_ID`:

```bash
gcloud services enable compute.googleapis.com --project YOUR_GCP_PROJECT_ID
gcloud services enable iam.googleapis.com --project YOUR_GCP_PROJECT_ID
```

Ou pelo console: [console.cloud.google.com/apis/library](https://console.cloud.google.com/apis/library) → pesquise "Compute Engine API" e ative.

---

## Estrutura

```
paperclip/
├── README.md                   ← você está aqui
└── infra/
    ├── main.tf                 # providers: google, cloudflare, random
    ├── variables.tf            # declaração de todas as variáveis
    ├── gce.tf                  # VM, IP estático, regras de firewall
    ├── cloudflare.tf           # Tunnel, roteamento, DNS CNAME
    ├── outputs.tf              # IP da VM, URL, comandos úteis pós-deploy
    ├── terraform.tfvars.example  # template — copie para terraform.tfvars
    ├── .gitignore              # protege tfvars, chaves e state local
    ├── credentials/
    │   └── README.md           # passo a passo para obter cada credencial
    └── scripts/
        └── startup.sh          # script executado na VM na primeira inicialização
```

---

## O que o startup.sh faz

Ao criar a VM, o GCE executa `startup.sh` automaticamente (uma única vez). Ele:

1. Instala Node.js 20 e pnpm
2. Instala PostgreSQL 16 e cria o banco `paperclip`
3. Cria o usuário de sistema `paperclip`
4. Escreve `/home/paperclip/paperclip.env` com as variáveis de ambiente
5. Cria e ativa o serviço systemd `paperclip` (ainda vai falhar — onboarding pendente)
6. Instala o `cloudflared` e ativa o serviço systemd com o token do tunnel

> **O onboarding do Paperclip não é feito automaticamente.** Ele requer input interativo no modo `authenticated/public` e deve ser feito manualmente após o boot. Ver seção "Onboarding manual correto" nas lições aprendidas.

O log completo fica em `/var/log/paperclip-startup.log` na VM.

---

## Deploy passo a passo

### 1. Autentique no GCP

```bash
gcloud auth application-default login
gcloud config set project YOUR_GCP_PROJECT_ID
```

### 2. Obtenha as credenciais CloudFlare

Siga `infra/credentials/README.md`. Você vai precisar de:

- **API Token** — com permissões `Zone:DNS:Edit` + `Account:Cloudflare Tunnel:Edit`
- **Zone ID** — nas configurações de `example.com` no dashboard
- **Account ID** — visível na URL do dashboard CloudFlare

### 3. Configure as variáveis

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
```

Edite `terraform.tfvars` e preencha:

```hcl
ssh_public_key        = "ssh-ed25519 AAAA..."   # cat ~/.ssh/id_ed25519.pub
cloudflare_api_token  = "..."
cloudflare_zone_id    = "..."
cloudflare_account_id = "..."
```

### 4. Rode o OpenTofu

```bash
cd infra
tofu init
tofu plan        # revise o que será criado
tofu apply       # cria tudo (~2 min)
```

O output mostrará:

```
app_url                = "https://paperclip.example.com"
vm_external_ip         = "34.x.x.x"
ssh_command            = "ssh ubuntu@34.x.x.x"
bootstrap_ceo_command  = "ssh ubuntu@34.x.x.x 'sudo -iu paperclip npx paperclipai auth bootstrap-ceo'"
startup_log_command    = "ssh ubuntu@34.x.x.x 'sudo tail -f /var/log/paperclip-startup.log'"
```

### 5. Aguarde o startup (~5 minutos)

Acompanhe o progresso:

```bash
ssh ubuntu@<IP> 'sudo tail -f /var/log/paperclip-startup.log'
```

### 6. Crie o primeiro usuário (CEO)

```bash
ssh ubuntu@<IP> 'sudo -iu paperclip npx paperclipai auth bootstrap-ceo'
```

Acesse https://paperclip.example.com e faça login.

---

## Operações do dia a dia

### SSH na VM

```bash
ssh ubuntu@<vm_external_ip>
```

### Ver logs da aplicação

```bash
sudo journalctl -u paperclip -f
```

### Ver logs do tunnel

```bash
sudo journalctl -u cloudflared -f
```

### Reiniciar serviços

```bash
sudo systemctl restart paperclip
sudo systemctl restart cloudflared
```

### Status dos serviços

```bash
sudo systemctl status paperclip cloudflared postgresql
```

### Diagnóstico do Paperclip

```bash
sudo -iu paperclip npx paperclipai doctor
sudo -iu paperclip npx paperclipai env
```

---

## Destruir a infra

```bash
cd infra
tofu destroy
```

> **Atenção:** isso remove a VM, o IP estático, o tunnel e o DNS. O banco de dados e todos os dados da aplicação serão perdidos.

---

## Recursos criados no GCP

| Recurso | Nome | Custo estimado |
|---|---|---|
| Compute Instance | `paperclip-server` | ~$50/mês (e2-standard-2) |
| Static IP | `paperclip-server-ip` | ~$3/mês |
| Firewall rules | `paperclip-allow-ssh`, `paperclip-allow-icmp` | grátis |

## Recursos criados no CloudFlare

| Recurso | Detalhe |
|---|---|
| Tunnel | `paperclip-gce` |
| DNS Record | `paperclip.example.com` CNAME → tunnel |

CloudFlare Tunnel é gratuito no plano Free.

---

## Lições aprendidas (primeira instalação — 2026-05-06)

Tudo que descobrimos na prática. Leia antes de fazer um novo deploy.

### Erros que cometemos — não repita

#### 1. Provider Cloudflare: recursos renomeados na v4

Os recursos antigos foram deprecados e removidos. Sempre use os novos nomes:

| Antigo (não usar) | Novo (correto) |
|---|---|
| `cloudflare_tunnel` | `cloudflare_zero_trust_tunnel_cloudflared` |
| `cloudflare_tunnel_config` | `cloudflare_zero_trust_tunnel_cloudflared_config` |

Se esquecer, o `tofu plan` avisa com `Deprecated Resource` e o `tofu apply` pode falhar.

#### 2. `http_host_header_rewrite` não existe no bloco `origin_request`

Argumento inválido que causa erro no `tofu plan`. O bloco correto é:

```hcl
origin_request {
  no_tls_verify          = false
  connect_timeout        = "30s"
  keep_alive_timeout     = "90s"
  keep_alive_connections = 100
}
```

#### 3. Ao renomear recursos no Terraform/OpenTofu, atualize TODOS os arquivos que os referenciam

Quando renomeamos `cloudflare_tunnel` → `cloudflare_zero_trust_tunnel_cloudflared`, o `outputs.tf` ainda referenciava o nome antigo e causou erro no `tofu plan`. Buscar por `cloudflare_tunnel.` em todos os arquivos antes de aplicar.

#### 4. APIs do GCP precisam ser ativadas antes do primeiro `tofu apply`

O `tofu apply` falha se as APIs não estiverem ativas. Ativar antes:

```bash
gcloud services enable compute.googleapis.com --project YOUR_GCP_PROJECT_ID
gcloud services enable iam.googleapis.com --project YOUR_GCP_PROJECT_ID
```

#### 5. NUNCA usar `npx paperclipai onboard --yes` em deploy de servidor

O flag `--yes` força o modo `local_trusted/private` e **ignora silenciosamente** todas as variáveis de ambiente de deployment (`PAPERCLIP_DEPLOYMENT_MODE`, `PAPERCLIP_DEPLOYMENT_EXPOSURE`, `PAPERCLIP_AUTH_PUBLIC_BASE_URL`). O servidor sobe com config errada e falha com:

```
authenticated public exposure requires auth.baseUrlMode=explicit
```

**Para servidor, sempre rodar sem `--yes` e responder o wizard interativamente**, escolhendo:
- Deployment mode: `authenticated`
- Exposure: `public`
- Base URL: `https://paperclip.example.com`

#### 6. `sudo -iu paperclip` falha quando o diretório atual não é acessível ao usuário `paperclip`

O erro `EACCES spawn sh /home/ubuntu` acontece porque o usuário `paperclip` não tem permissão de leitura em `/home/ubuntu`. Sempre incluir `cd /home/paperclip` no início do comando:

```bash
# Errado
sudo -u paperclip bash -c 'npx paperclipai ...'

# Correto
sudo -u paperclip bash -c 'cd /home/paperclip && npx paperclipai ...'
```

#### 7. O startup.sh não captura bem o output do onboarding interativo

O onboarding precisou ser feito manualmente na VM após o primeiro boot. O `startup.sh` atual instala tudo mas não completa o onboarding corretamente porque o wizard requer input interativo para deploy em modo `authenticated`. Em deploys futuros, o fluxo correto é:

1. `tofu apply` → VM sobe, instala Node.js, PostgreSQL, cloudflared
2. SSH na VM → rodar onboarding manualmente (ver seção abaixo)
3. Criar usuário CEO
4. Subir o serviço

---

### O que funcionou bem

- **Cloudflare Tunnel** elimina a necessidade de Nginx, Certbot e Let's Encrypt. Certificado TLS gerenciado automaticamente pelo CloudFlare.
- **PostgreSQL local** na VM funciona perfeitamente. Backup automático a cada 60 minutos está habilitado pelo próprio Paperclip em `/home/paperclip/.paperclip/instances/default/data/backups`.
- **Token do tunnel via GCE metadata** funciona corretamente — o `startup.sh` lê com `curl -H "Metadata-Flavor: Google"`.
- **Chave SSH existente** (`~/.ssh/github`) funciona normalmente com `ssh -i ~/.ssh/github ubuntu@<IP>`.
- **75 migrations do banco** aplicadas automaticamente pelo Paperclip na primeira execução do onboard. Se precisar re-rodar o onboard, as migrations já aplicadas são detectadas e puladas.

---

### Onboarding manual correto (para usar em novos deploys)

```bash
# 1. Para o serviço se estiver rodando
sudo systemctl stop paperclip

# 2. Remove config antiga se existir (mantém master.key e .env)
sudo rm -f /home/paperclip/.paperclip/instances/default/config.json

# 3. Onboarding interativo como usuário paperclip
sudo -u paperclip bash -c '
  cd /home/paperclip
  set -a; source /home/paperclip/paperclip.env; set +a
  npx paperclipai onboard
'
# No wizard: authenticated / public / https://paperclip.example.com

# 4. Sobe o serviço
sudo systemctl start paperclip
sudo journalctl -u paperclip -f

# 5. Cria o primeiro usuário (CEO)
sudo -u paperclip bash -c '
  cd /home/paperclip
  set -a; source /home/paperclip/paperclip.env; set +a
  npx paperclipai auth bootstrap-ceo
'
```
