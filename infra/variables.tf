variable "gcp_project_id" {
  description = "ID do projeto GCP (ex: meu-projeto-123456)"
  type        = string
}

variable "gcp_region" {
  description = "Região GCP"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "Zona GCP"
  type        = string
  default     = "us-central1-a"
}

variable "gcp_machine_type" {
  description = "Tipo de máquina GCE"
  type        = string
  default     = "e2-standard-2" # 2 vCPU, 8GB RAM
}

variable "gcp_disk_size_gb" {
  description = "Tamanho do disco de boot em GB"
  type        = number
  default     = 50
}

variable "cloudflare_api_token" {
  description = "API Token do CloudFlare (precisa de permissões: Zone:DNS:Edit + Account:Cloudflare Tunnel:Edit)"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Zone ID do seu domínio no CloudFlare (Settings > General > Zone ID)"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Account ID do CloudFlare (visível na URL do dashboard)"
  type        = string
}

variable "ssh_public_key" {
  description = "Chave SSH pública para acesso à VM (conteúdo de ~/.ssh/id_ed25519.pub ou similar)"
  type        = string
}

variable "app_domain" {
  description = "Domínio completo da aplicação (ex: paperclip.example.com)"
  type        = string
  default     = "paperclip.example.com"
}

variable "app_subdomain" {
  description = "Subdomínio (parte antes do domínio raiz)"
  type        = string
  default     = "paperclip"
}
