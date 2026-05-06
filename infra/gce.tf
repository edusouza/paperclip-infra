locals {
  vm_name = "paperclip-server"
  vm_tags = ["paperclip", "ssh-allowed"]
}

# IP estático para SSH
resource "google_compute_address" "paperclip" {
  name   = "${local.vm_name}-ip"
  region = var.gcp_region
}

# Firewall: só SSH (porta 22) — HTTP/HTTPS vai pelo Cloudflare Tunnel
resource "google_compute_firewall" "ssh" {
  name    = "paperclip-allow-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["ssh-allowed"]
}

# Firewall: ICMP (ping)
resource "google_compute_firewall" "icmp" {
  name    = "paperclip-allow-icmp"
  network = "default"

  allow {
    protocol = "icmp"
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = local.vm_tags
}

resource "google_compute_instance" "paperclip" {
  name         = local.vm_name
  machine_type = var.gcp_machine_type
  zone         = var.gcp_zone
  tags         = local.vm_tags

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = var.gcp_disk_size_gb
      type  = "pd-ssd"
    }
  }

  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.paperclip.address
    }
  }

  metadata = {
    ssh-keys = "ubuntu:${var.ssh_public_key}"

    # Configurações passadas para o startup script
    paperclip-domain        = var.app_domain
    paperclip-tunnel-token  = cloudflare_zero_trust_tunnel_cloudflared.paperclip.tunnel_token
    paperclip-auth-secret   = random_password.better_auth_secret.result
  }

  metadata_startup_script = file("${path.module}/scripts/startup.sh")

  service_account {
    scopes = ["cloud-platform"]
  }

  lifecycle {
    ignore_changes = [metadata["paperclip-tunnel-token"]]
  }
}
