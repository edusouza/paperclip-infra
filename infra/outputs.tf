output "vm_external_ip" {
  description = "IP público da VM (para SSH)"
  value       = google_compute_address.paperclip.address
}

output "ssh_command" {
  description = "Comando para conectar via SSH"
  value       = "ssh ubuntu@${google_compute_address.paperclip.address}"
}

output "app_url" {
  description = "URL pública da aplicação"
  value       = "https://${var.app_domain}"
}

output "tunnel_id" {
  description = "ID do Cloudflare Tunnel"
  value       = cloudflare_zero_trust_tunnel_cloudflared.paperclip.id
}

output "startup_log_command" {
  description = "Comando para ver o log de startup na VM"
  value       = "ssh ubuntu@${google_compute_address.paperclip.address} 'sudo tail -f /var/log/paperclip-startup.log'"
}

output "bootstrap_ceo_command" {
  description = "Comando para criar o primeiro usuário após o startup"
  value       = "ssh ubuntu@${google_compute_address.paperclip.address} 'sudo -iu paperclip npx paperclipai auth bootstrap-ceo'"
}
