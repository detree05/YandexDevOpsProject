terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.87.0"
}

provider "yandex" {
  service_account_key_file = "./authorized_key.json"
  folder_id                = local.folder_id
  zone                     = "ru-central1-a"
}

locals {
  folder_id = var.folder_id
  service-accounts = toset([
    "bingo-sa",
  ])
  bingo-sa-roles = toset([
    "editor"
  ])
}
  
resource "yandex_vpc_network" "bingo-network" {}

resource "yandex_vpc_subnet" "bingo-subnet" {
  zone           = "ru-central1-a"
  network_id     = "${yandex_vpc_network.bingo-network.id}"
  v4_cidr_blocks = ["10.5.0.0/24"]
}

resource "yandex_dns_zone" "dns-zone" {
  name        = "bingo-dns-zone"
  description = "BINGO DNS Public Zone"

  labels = {
    label1 = "bingo-public"
  }

  zone    = "neverservers.ru."
  public  = true
}

resource "yandex_dns_recordset" "dns-rs" {
  zone_id = yandex_dns_zone.dns-zone.id
  name    = "bingo.neverservers.ru."
  type    = "A"
  ttl     = 200
  data    = ["${yandex_compute_instance.bingo-service.network_interface.0.nat_ip_address}"]
}

resource "yandex_iam_service_account" "service-accounts" {
  for_each = local.service-accounts
  name     = each.key
}

resource "yandex_resourcemanager_folder_iam_member" "bingo-roles" {
  for_each  = local.bingo-sa-roles
  folder_id = local.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["bingo-sa"].id}"
  role      = each.key
}

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

resource "yandex_compute_instance" "bingo-db" {
  platform_id        = "standard-v2"
  service_account_id = yandex_iam_service_account.service-accounts["bingo-sa"].id
  resources {
    cores         = 2
    memory        = 4
    core_fraction = 5
  }
  scheduling_policy {
    preemptible = true
  }
  network_interface {
    subnet_id = "${yandex_vpc_subnet.bingo-subnet.id}"
    ip_address = "10.5.0.15"
	nat = true
  }
  boot_disk {
    initialize_params {
      type = "network-hdd"
      size = "30"
      image_id = data.yandex_compute_image.ubuntu.id
    }
  }
  metadata = {
    serial-port-enable = 1
    user-data = file("${path.module}/database/cloud-init.yaml")
  }
}

resource "yandex_compute_instance" "bingo-service" {
  platform_id        = "standard-v2"
  service_account_id = yandex_iam_service_account.service-accounts["bingo-sa"].id
  resources {
    cores         = 2
    memory        = 4
    core_fraction = 5
  }
  scheduling_policy {
    preemptible = true
  }
  network_interface {
    subnet_id = "${yandex_vpc_subnet.bingo-subnet.id}"
    ip_address = "10.5.0.10"
    nat = true
  }
  boot_disk {
    initialize_params {
      type = "network-hdd"
      size = "30"
      image_id = data.yandex_compute_image.ubuntu.id
    }
  }
  metadata = {
    serial-port-enable = 1
    user-data = file("${path.module}/service/cloud-init.yaml")
  }
  depends_on = [yandex_compute_instance.bingo-db]
}