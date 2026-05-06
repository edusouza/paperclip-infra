#!/bin/bash
set -euo pipefail
exec > /var/log/paperclip-startup.log 2>&1

echo "=== Paperclip VM startup: $(date) ==="

# ── Helpers ──────────────────────────────────────────────────────────────────

metadata() {
  curl -sf \
    -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/attributes/${1}"
}

# ── Lê configurações do metadata ─────────────────────────────────────────────

APP_DOMAIN="$(metadata paperclip-domain)"
TUNNEL_TOKEN="$(metadata paperclip-tunnel-token)"
AUTH_SECRET="$(metadata paperclip-auth-secret)"

# ── Sistema base ─────────────────────────────────────────────────────────────

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
  curl wget gnupg2 ca-certificates \
  lsb-release software-properties-common \
  git unzip jq

# ── Node.js 20 ───────────────────────────────────────────────────────────────

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
corepack enable
corepack prepare pnpm@latest --activate

echo "Node.js: $(node --version)"
echo "pnpm:    $(pnpm --version)"

# ── PostgreSQL 16 ────────────────────────────────────────────────────────────

curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
  | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] \
  https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list
apt-get update -qq
apt-get install -y postgresql-16

systemctl enable --now postgresql

# Cria usuário e banco de dados
sudo -u postgres psql -c \
  "CREATE USER paperclip WITH PASSWORD 'paperclip' CREATEDB;" 2>/dev/null || true
sudo -u postgres psql -c \
  "CREATE DATABASE paperclip OWNER paperclip;" 2>/dev/null || true

# ── Usuário do sistema ────────────────────────────────────────────────────────

useradd --system --create-home --shell /bin/bash paperclip || true

# ── Arquivo de ambiente ───────────────────────────────────────────────────────

cat > /home/paperclip/paperclip.env <<EOF
DATABASE_URL=postgresql://paperclip:paperclip@localhost:5432/paperclip
PORT=3100
HOST=127.0.0.1
SERVER_UI=true
BETTER_AUTH_SECRET=${AUTH_SECRET}
PAPERCLIP_DEPLOYMENT_MODE=authenticated
PAPERCLIP_DEPLOYMENT_EXPOSURE=public
PAPERCLIP_AUTH_PUBLIC_BASE_URL=https://${APP_DOMAIN}
PAPERCLIP_ALLOWED_HOSTNAMES=${APP_DOMAIN}
EOF

chmod 600 /home/paperclip/paperclip.env
chown paperclip:paperclip /home/paperclip/paperclip.env

# ── Systemd: paperclip.service ────────────────────────────────────────────────
# NOTA: o onboarding NÃO é feito aqui porque requer input interativo no modo
# authenticated/public. Deve ser feito manualmente após o boot da VM.
# Ver seção "Onboarding manual correto" no README.md.

cat > /etc/systemd/system/paperclip.service <<'UNIT'
[Unit]
Description=Paperclip control plane
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=paperclip
Group=paperclip
WorkingDirectory=/home/paperclip
EnvironmentFile=/home/paperclip/paperclip.env
ExecStart=/usr/bin/npx paperclipai run
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now paperclip

# ── Cloudflare Tunnel (cloudflared) ───────────────────────────────────────────

ARCH=$(dpkg --print-architecture)
curl -fsSL \
  "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb" \
  -o /tmp/cloudflared.deb
dpkg -i /tmp/cloudflared.deb
rm /tmp/cloudflared.deb

cat > /etc/systemd/system/cloudflared.service <<UNIT
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/cloudflared tunnel --no-autoupdate run --token ${TUNNEL_TOKEN}
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now cloudflared

echo "=== Startup concluído: $(date) ==="
echo "Acesse: https://${APP_DOMAIN}"
echo ""
echo "Para criar o primeiro usuário (CEO), execute na VM:"
echo "  sudo -iu paperclip npx paperclipai auth bootstrap-ceo"
