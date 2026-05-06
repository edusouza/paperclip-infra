# Secret aleatório para o tunnel (32 bytes em base64)
resource "random_bytes" "tunnel_secret" {
  length = 32
}

# Secret para Better Auth
resource "random_password" "better_auth_secret" {
  length  = 48
  special = false
}

# Cloudflare Tunnel
resource "cloudflare_zero_trust_tunnel_cloudflared" "paperclip" {
  account_id = var.cloudflare_account_id
  name       = "paperclip-gce"
  secret     = random_bytes.tunnel_secret.base64
}

# Configuração do roteamento dentro do tunnel
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "paperclip" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.paperclip.id

  config {
    ingress_rule {
      hostname = var.app_domain
      service  = "http://localhost:3100"
      origin_request {
        no_tls_verify          = false
        connect_timeout        = "30s"
        keep_alive_timeout     = "90s"
        keep_alive_connections = 100
      }
    }

    # Regra catch-all obrigatória
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# DNS: CNAME paperclip.eduardosouza.dev → tunnel
resource "cloudflare_record" "paperclip" {
  zone_id = var.cloudflare_zone_id
  name    = var.app_subdomain
  content = "${cloudflare_zero_trust_tunnel_cloudflared.paperclip.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}
