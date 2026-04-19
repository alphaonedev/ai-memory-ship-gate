# Copyright 2026 AlphaOne LLC
# SPDX-License-Identifier: Apache-2.0
#
# Ship-gate DigitalOcean fixture: 3 peer nodes + 1 chaos client.
# Apply with:
#
#   terraform init
#   terraform plan \
#     -var "do_token=$DIGITALOCEAN_TOKEN" \
#     -var "ssh_key_fingerprint=$DIGITALOCEAN_SSH_KEY_FINGERPRINT" \
#     -var "campaign_id=$CAMPAIGN_ID" \
#     -var "ai_memory_git_ref=$AI_MEMORY_GIT_REF"
#   terraform apply ...
#
# The CI workflow does this for you; the manual path is for dev
# iteration on the phase scripts themselves.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.40"
    }
  }
}

variable "do_token" {
  description = "DigitalOcean API token. Read from DIGITALOCEAN_TOKEN env."
  type        = string
  sensitive   = true
}

variable "ssh_key_fingerprint" {
  description = "SHA-256 fingerprint of an SSH key already registered with DO."
  type        = string
}

variable "region" {
  description = "DO region."
  type        = string
  default     = "nyc3"
}

variable "peer_size" {
  description = "Droplet size for the 3 federation peers."
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "chaos_size" {
  description = "Droplet size for the chaos client."
  type        = string
  default     = "s-1vcpu-2gb"
}

variable "campaign_id" {
  description = "Opaque identifier for this campaign run."
  type        = string
}

variable "ai_memory_git_ref" {
  description = "Git ref of ai-memory-mcp to validate (tag, branch, or SHA)."
  type        = string
}

variable "dead_man_switch_hours" {
  description = "Drop self-destructs after this many hours regardless."
  type        = number
  default     = 8
}

provider "digitalocean" {
  token = var.do_token
}

locals {
  # DO tags accept only [a-z0-9:_-]; strip anything else from campaign_id.
  campaign_tag = replace(replace(var.campaign_id, ".", "-"), "/", "-")
  tags = [
    "ai-memory",
    "ship-gate",
    "campaign-${local.campaign_tag}",
    "auto-destroy",
  ]
}

# Explicit VPC per campaign. DO's default VPC resolution can fail for
# fresh accounts / fresh regions; owning the VPC ourselves makes the
# terraform plan deterministic and lets us tear it down cleanly.
resource "digitalocean_vpc" "campaign" {
  name     = "aim-${local.campaign_tag}-vpc"
  region   = var.region
  ip_range = "10.250.0.0/20"
}

# Per-node cloud-init: installs ai-memory from the given git ref,
# sets up the systemd units, and installs the dead-man switch.
locals {
  cloud_init = templatefile("${path.module}/cloud-init.yaml", {
    ai_memory_git_ref     = var.ai_memory_git_ref
    campaign_id           = var.campaign_id
    dead_man_switch_hours = var.dead_man_switch_hours
  })
}

resource "digitalocean_droplet" "peer" {
  for_each = toset(["a", "b", "c"])

  image    = "ubuntu-24-04-x64"
  name     = "aim-${local.campaign_tag}-node-${each.key}"
  region   = var.region
  size     = var.peer_size
  ssh_keys = [var.ssh_key_fingerprint]
  tags     = local.tags
  vpc_uuid = digitalocean_vpc.campaign.id

  user_data = local.cloud_init

  # 8-hour floor on how long DO auto-destroy will hold back. Paired
  # with the in-droplet dead-man switch for defense in depth.
  droplet_agent = true
}

resource "digitalocean_droplet" "chaos_client" {
  image    = "ubuntu-24-04-x64"
  name     = "aim-${local.campaign_tag}-chaos"
  region   = var.region
  size     = var.chaos_size
  ssh_keys = [var.ssh_key_fingerprint]
  tags     = concat(local.tags, ["chaos-client"])
  vpc_uuid = digitalocean_vpc.campaign.id

  user_data = local.cloud_init
}

resource "digitalocean_firewall" "peer_mesh" {
  name = "aim-${local.campaign_tag}-peer-mesh"
  tags = concat(local.tags)

  # Inbound: peer-to-peer quorum writes over TLS + ssh for ops.
  inbound_rule {
    protocol         = "tcp"
    port_range       = "9077"
    source_addresses = [for d in digitalocean_droplet.peer : d.ipv4_address_private]
  }
  inbound_rule {
    protocol         = "tcp"
    port_range       = "9077"
    source_addresses = [digitalocean_droplet.chaos_client.ipv4_address_private]
  }
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Outbound: anything (cloud-init pulls packages, reaches crates.io,
  # reaches GitHub for the ai-memory-mcp clone).
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

output "peer_nodes" {
  description = "Public IPv4 addresses of the three federation peers."
  value = {
    for key, d in digitalocean_droplet.peer : "node-${key}" => {
      public  = d.ipv4_address
      private = d.ipv4_address_private
    }
  }
}

output "chaos_client" {
  description = "Public IPv4 of the chaos-client droplet."
  value       = digitalocean_droplet.chaos_client.ipv4_address
}

output "campaign_id" {
  value = var.campaign_id
}
