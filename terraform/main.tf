terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "xylos-terraform-state" 
    prefix = "migration-tool/state"
  }
}
provider "google" {
  project = var.project_id
  region  = "us-central1"
  zone    = "us-central1-a"
}

resource "google_service_account" "default" {
  account_id = "xylos-automation"
  display_name = "xylos-automation"
}
resource "google_project_iam_member" "sa_editor" {
  project = var.project_id
  role = "roles/editor"
  member = "serviceAccount:${google_service_account.default.email}"
}

resource "google_compute_instance" "default" {
  name = "migration_tool"
  machine_type = "e2-micro"
  zone = "us-central1-a"
  tags = ["automation"]
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      labels = {
        label = "testing"
      }
    }
  }
  scratch_disk {
    interface = "NVME"
  }

  network_interface {
    network = "default"

    access_config {
      nat_ip = google_compute_address.static_ip.address
    }
  }

  metadata = {
    foo = "bar"
  }
  metadata_startup_script = templatefile("${path.module}/script.sh", {
    domain_name = var.domain_name
    email       = var.email
  })
}
resource "google_compute_address" "static_ip" {
    name = "migration_tool_ip"
    region = "us-central1"
}
resource "google_compute_firewall" "security_rules" {
  name = "allow-web"
  network = "default"
  allow {
    protocol = "tcp"
    ports = ["443", "80"]
  }
  target_tags = ["automation"]
  source_ranges = ["0.0.0.0/0"]
}