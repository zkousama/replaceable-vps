variable "server_name" {
  type        = string
  description = "Name on the provider's side, and the Ansible inventory host."
  default     = "prod"
}

variable "server_type" {
  type        = string
  description = <<-EOT
    Hetzner server type. The one thing to know: a rescale can move within a
    line but not between them, so cx22 to cx32 is an in-place resize and cpx22
    to cx33 is a replacement. docs/replace-a-server.md is the second case.

    Move this default the moment a replacement applies cleanly. Leaving it at
    the old value means the next plan quietly proposes rescaling back.
  EOT
  default     = "cx22"
}

variable "server_location" {
  type        = string
  description = "Datacentre location, e.g. nbg1 or hel1."
  default     = "nbg1"
}

variable "server_image" {
  type        = string
  description = <<-EOT
    An OS image slug for a fresh box ("ubuntu-24.04"), or the numeric id of a
    snapshot to clone. Changing this does not rebuild anything by itself: see
    the lifecycle block in server.tf.
  EOT
  default     = "ubuntu-24.04"
}

variable "ssh_key_name" {
  type        = string
  description = "Name of a key already uploaded to the provider project."
}

variable "ssh_port" {
  type        = number
  description = <<-EOT
    Port sshd listens on once the bootstrap playbook has moved it.

    Ansible reads the same number from its own group_vars and the 2 have to
    agree. An earlier version of this had a list here and a scalar there,
    which is a quiet way to end up with a firewall opening a port sshd is not
    listening on.
  EOT
  default     = 22
}

variable "allow_default_ssh_port" {
  type        = bool
  description = <<-EOT
    Keep 22 open alongside ssh_port. True until the bootstrap playbook has
    moved sshd, false afterwards.

    The first connection to a fresh machine has to land on 22, so a firewall
    that only opens the new port locks you out of the box you are about to
    configure.
  EOT
  default     = true
}

variable "ssh_source_cidrs" {
  type        = list(string)
  description = <<-EOT
    Who may reach SSH. A fixed address or a VPN range is the point of this; if
    it ends up as ["0.0.0.0/0", "::/0"] then fail2ban and key-only auth are
    what is left, and the playbook sets up both.

    No default, so this is a decision rather than something you inherit.
  EOT

  validation {
    condition     = length(var.ssh_source_cidrs) > 0
    error_message = "ssh_source_cidrs is empty, which builds a firewall rule with no sources. Name at least one CIDR, or [\"0.0.0.0/0\", \"::/0\"] if you mean anywhere."
  }
}

variable "web_ports" {
  type        = list(number)
  description = "Ports open to the internet. 80 redirects, 443 serves."
  default     = [80, 443]
}

variable "enable_backups" {
  type        = bool
  description = <<-EOT
    The provider's own daily backups, billed at a percentage of the server.
    They are a convenience, not a strategy: they live in the same account as
    the thing they protect. Keep a logical dump somewhere else as well.
  EOT
  default     = true
}

variable "delete_protection" {
  type        = bool
  description = "Provider-side flag. Blocks a delete through the API or console."
  default     = true
}

variable "rebuild_protection" {
  type        = bool
  description = "Provider-side flag. Blocks a rebuild from an image."
  default     = true
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Zone the records below belong to."
}

variable "a_records" {
  type        = list(string)
  description = <<-EOT
    Names that should resolve to the server's IPv4 address. "@" for the apex.
    Every name here is one the migration runbook does not have to think about,
    because the value is a reference rather than an address.
  EOT
  default     = ["@", "www"]
}

variable "aaaa_records" {
  type        = list(string)
  description = "Names that should resolve to the server's IPv6 address."
  default     = ["@", "www"]
}

variable "proxied" {
  type        = bool
  description = <<-EOT
    Whether the records go through Cloudflare's proxy. Proxied records hide the
    origin address and pin their TTL to automatic, which is also why a
    cutover needs no TTL lowering beforehand.
  EOT
  default     = true
}
