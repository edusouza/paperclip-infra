# Paperclip — GCP + CloudFlare Infrastructure

Deploy of [Paperclip](https://paperclip.ing) on a GCE VM with Cloudflare Tunnel, provisioned via OpenTofu.

## Architecture

```
                        ┌─────────────────────────────────────┐
                        │         GCE VM (us-central1-a)       │
                        │         e2-standard-2 / Ubuntu 22.04 │
                        │                                       │
 User                   │  ┌────────────┐   ┌───────────────┐  │
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

**Why Cloudflare Tunnel?**
- No ports 80/443 open on the VM — the tunnel connects outbound
- TLS automatically managed by CloudFlare (no Certbot/Let's Encrypt needed)
- DDoS protection and CDN included
- The VM's real IP stays hidden

---

## Prerequisites

| Tool | Version | Installation |
|---|---|---|
| OpenTofu | >= 1.6 | `winget install OpenTofu.OpenTofu` |
| gcloud CLI | any | [cloud.google.com/sdk](https://cloud.google.com/sdk/docs/install) |
| SSH key pair | — | `ssh-keygen -t ed25519` |

### Required GCP APIs

Before the first `tofu apply`, enable the APIs below on your `YOUR_GCP_PROJECT_ID` project:

```bash
gcloud services enable compute.googleapis.com --project YOUR_GCP_PROJECT_ID
gcloud services enable iam.googleapis.com --project YOUR_GCP_PROJECT_ID
```

Or via the console: [console.cloud.google.com/apis/library](https://console.cloud.google.com/apis/library) → search "Compute Engine API" and enable.

---

## Structure

```
paperclip/
├── README.md                   ← you are here
├── README.pt.md                ← Portuguese version
└── infra/
    ├── main.tf                 # providers: google, cloudflare, random
    ├── variables.tf            # declaration of all variables
    ├── gce.tf                  # VM, static IP, firewall rules
    ├── cloudflare.tf           # Tunnel, routing, DNS CNAME
    ├── outputs.tf              # VM IP, URL, useful post-deploy commands
    ├── terraform.tfvars.example  # template — copy to terraform.tfvars
    ├── .gitignore              # protects tfvars, keys and local state
    ├── credentials/
    │   └── README.md           # step-by-step to obtain each credential
    └── scripts/
        └── startup.sh          # script executed on the VM on first boot
```

---

## What startup.sh does

When the VM is created, GCE runs `startup.sh` automatically (once). It:

1. Installs Node.js 20 and pnpm
2. Installs PostgreSQL 16 and creates the `paperclip` database
3. Creates the `paperclip` system user
4. Writes `/home/paperclip/paperclip.env` with environment variables
5. Creates and enables the `paperclip` systemd service (will still fail — onboarding pending)
6. Installs `cloudflared` and enables the systemd service with the tunnel token

> **Paperclip onboarding is not done automatically.** It requires interactive input in `authenticated/public` mode and must be done manually after boot. See the "Correct manual onboarding" section in lessons learned.

The full log is at `/var/log/paperclip-startup.log` on the VM.

---

## Step-by-step Deploy

### 1. Authenticate with GCP

```bash
gcloud auth application-default login
gcloud config set project YOUR_GCP_PROJECT_ID
```

### 2. Obtain CloudFlare credentials

Follow `infra/credentials/README.md`. You will need:

- **API Token** — with `Zone:DNS:Edit` + `Account:Cloudflare Tunnel:Edit` permissions
- **Zone ID** — in the `example.com` settings on the dashboard
- **Account ID** — visible in the CloudFlare dashboard URL

### 3. Configure variables

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and fill in:

```hcl
ssh_public_key        = "ssh-ed25519 AAAA..."   # cat ~/.ssh/id_ed25519.pub
cloudflare_api_token  = "..."
cloudflare_zone_id    = "..."
cloudflare_account_id = "..."
```

### 4. Run OpenTofu

```bash
cd infra
tofu init
tofu plan        # review what will be created
tofu apply       # creates everything (~2 min)
```

The output will show:

```
app_url                = "https://paperclip.example.com"
vm_external_ip         = "34.x.x.x"
ssh_command            = "ssh ubuntu@34.x.x.x"
bootstrap_ceo_command  = "ssh ubuntu@34.x.x.x 'sudo -iu paperclip npx paperclipai auth bootstrap-ceo'"
startup_log_command    = "ssh ubuntu@34.x.x.x 'sudo tail -f /var/log/paperclip-startup.log'"
```

### 5. Wait for startup (~5 minutes)

Follow the progress:

```bash
ssh ubuntu@<IP> 'sudo tail -f /var/log/paperclip-startup.log'
```

### 6. Create the first user (CEO)

```bash
ssh ubuntu@<IP> 'sudo -iu paperclip npx paperclipai auth bootstrap-ceo'
```

Visit https://paperclip.example.com and log in.

---

## Day-to-day Operations

### SSH into the VM

```bash
ssh ubuntu@<vm_external_ip>
```

### View application logs

```bash
sudo journalctl -u paperclip -f
```

### View tunnel logs

```bash
sudo journalctl -u cloudflared -f
```

### Restart services

```bash
sudo systemctl restart paperclip
sudo systemctl restart cloudflared
```

### Service status

```bash
sudo systemctl status paperclip cloudflared postgresql
```

### Paperclip diagnostics

```bash
sudo -iu paperclip npx paperclipai doctor
sudo -iu paperclip npx paperclipai env
```

---

## Destroy the infrastructure

```bash
cd infra
tofu destroy
```

> **Warning:** this removes the VM, the static IP, the tunnel, and the DNS. The database and all application data will be lost.

---

## Resources created on GCP

| Resource | Name | Estimated Cost |
|---|---|---|
| Compute Instance | `paperclip-server` | ~$50/month (e2-standard-2) |
| Static IP | `paperclip-server-ip` | ~$3/month |
| Firewall rules | `paperclip-allow-ssh`, `paperclip-allow-icmp` | free |

## Resources created on CloudFlare

| Resource | Detail |
|---|---|
| Tunnel | `paperclip-gce` |
| DNS Record | `paperclip.example.com` CNAME → tunnel |

CloudFlare Tunnel is free on the Free plan.

---

## Lessons Learned (first install — 2026-05-06)

Everything we discovered in practice. Read before doing a new deploy.

### Mistakes we made — don't repeat

#### 1. Cloudflare provider: resources renamed in v4

Old resources were deprecated and removed. Always use the new names:

| Old (don't use) | New (correct) |
|---|---|
| `cloudflare_tunnel` | `cloudflare_zero_trust_tunnel_cloudflared` |
| `cloudflare_tunnel_config` | `cloudflare_zero_trust_tunnel_cloudflared_config` |

If you forget, `tofu plan` warns with `Deprecated Resource` and `tofu apply` may fail.

#### 2. `http_host_header_rewrite` does not exist in the `origin_request` block

Invalid argument that causes an error on `tofu plan`. The correct block is:

```hcl
origin_request {
  no_tls_verify          = false
  connect_timeout        = "30s"
  keep_alive_timeout     = "90s"
  keep_alive_connections = 100
}
```

#### 3. When renaming resources in Terraform/OpenTofu, update ALL files that reference them

When we renamed `cloudflare_tunnel` → `cloudflare_zero_trust_tunnel_cloudflared`, `outputs.tf` still referenced the old name and caused an error on `tofu plan`. Search for `cloudflare_tunnel.` across all files before applying.

#### 4. GCP APIs must be enabled before the first `tofu apply`

`tofu apply` fails if the APIs are not active. Enable them first:

```bash
gcloud services enable compute.googleapis.com --project YOUR_GCP_PROJECT_ID
gcloud services enable iam.googleapis.com --project YOUR_GCP_PROJECT_ID
```

#### 5. NEVER use `npx paperclipai onboard --yes` for server deployments

The `--yes` flag forces `local_trusted/private` mode and **silently ignores** all deployment environment variables (`PAPERCLIP_DEPLOYMENT_MODE`, `PAPERCLIP_DEPLOYMENT_EXPOSURE`, `PAPERCLIP_AUTH_PUBLIC_BASE_URL`). The server starts with wrong config and fails with:

```
authenticated public exposure requires auth.baseUrlMode=explicit
```

**For servers, always run without `--yes` and answer the wizard interactively**, choosing:
- Deployment mode: `authenticated`
- Exposure: `public`
- Base URL: `https://paperclip.example.com`

#### 6. `sudo -iu paperclip` fails when the current directory is not accessible to the `paperclip` user

The error `EACCES spawn sh /home/ubuntu` happens because the `paperclip` user doesn't have read permission on `/home/ubuntu`. Always include `cd /home/paperclip` at the start of the command:

```bash
# Wrong
sudo -u paperclip bash -c 'npx paperclipai ...'

# Correct
sudo -u paperclip bash -c 'cd /home/paperclip && npx paperclipai ...'
```

#### 7. startup.sh does not properly capture interactive onboarding output

Onboarding had to be done manually on the VM after the first boot. The current `startup.sh` installs everything but doesn't complete onboarding correctly because the wizard requires interactive input for `authenticated` mode deployment. For future deploys, the correct flow is:

1. `tofu apply` → VM boots, installs Node.js, PostgreSQL, cloudflared
2. SSH into VM → run onboarding manually (see section below)
3. Create CEO user
4. Start the service

---

### What worked well

- **Cloudflare Tunnel** eliminates the need for Nginx, Certbot and Let's Encrypt. TLS certificate automatically managed by CloudFlare.
- **Local PostgreSQL** on the VM works perfectly. Automatic backup every 60 minutes is enabled by Paperclip itself at `/home/paperclip/.paperclip/instances/default/data/backups`.
- **Tunnel token via GCE metadata** works correctly — `startup.sh` reads it with `curl -H "Metadata-Flavor: Google"`.
- **Existing SSH key** (`~/.ssh/github`) works normally with `ssh -i ~/.ssh/github ubuntu@<IP>`.
- **75 database migrations** applied automatically by Paperclip on the first onboard run. If you need to re-run onboard, already applied migrations are detected and skipped.

---

### Correct manual onboarding (for use in new deploys)

```bash
# 1. Stop the service if it's running
sudo systemctl stop paperclip

# 2. Remove old config if it exists (keeps master.key and .env)
sudo rm -f /home/paperclip/.paperclip/instances/default/config.json

# 3. Interactive onboarding as the paperclip user
sudo -u paperclip bash -c '
  cd /home/paperclip
  set -a; source /home/paperclip/paperclip.env; set +a
  npx paperclipai onboard
'
# In the wizard: authenticated / public / https://paperclip.example.com

# 4. Start the service
sudo systemctl start paperclip
sudo journalctl -u paperclip -f

# 5. Create the first user (CEO)
sudo -u paperclip bash -c '
  cd /home/paperclip
  set -a; source /home/paperclip/paperclip.env; set +a
  npx paperclipai auth bootstrap-ceo
'
```
