data "hcloud_ssh_key" "ops" {
  name = var.ssh_key_name
}

# The outer layer, at the provider's edge, before a packet reaches the machine.
# The playbook sets up a host firewall as well; this one drops traffic that
# never gets far enough to be logged on the box.
resource "hcloud_firewall" "baseline" {
  name = "${var.server_name}-baseline"

  dynamic "rule" {
    for_each = toset(var.web_ports)
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = rule.value
      source_ips = ["0.0.0.0/0", "::/0"]
    }
  }

  dynamic "rule" {
    for_each = toset(var.ssh_ports)
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = rule.value
      source_ips = var.ssh_source_cidrs
    }
  }

  # Being pingable is worth more than the obscurity of not being. Every
  # uptime checker and half of network debugging wants ICMP.
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "prod" {
  name         = var.server_name
  server_type  = var.server_type
  location     = var.server_location
  image        = var.server_image
  ssh_keys     = [data.hcloud_ssh_key.ops.id]
  backups      = var.enable_backups
  firewall_ids = [hcloud_firewall.baseline.id]

  delete_protection  = var.delete_protection
  rebuild_protection = var.rebuild_protection

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  lifecycle {
    # The provider-side flags above stop a delete through the API or the
    # console. They do NOT stop `tofu destroy`, which is a different path, so
    # without it a mistyped `tofu destroy` takes the machine with it. It cannot be a variable: OpenTofu still does not accept them in
    # meta-arguments.
    #
    # A deliberate replacement means commenting this line out, in a commit
    # whose message says why, and putting it back in the same sitting. The
    # commit pair is the audit trail. See docs/replace-a-server.md.
    prevent_destroy = true

    ignore_changes = [
      # The image slug resolves to a numeric id on the provider's side and the
      # ids rotate underneath it, so a plan would otherwise offer to rebuild
      # the server every time the distribution publishes a new build.
      #
      # This is also why booting from a snapshot is driven by
      # `-replace=hcloud_server.prod` rather than by editing server_image and
      # waiting for a diff: there is no diff. Setting the variable says which
      # image the new machine comes from; the -replace is what asks for a new
      # machine at all.
      image,
    ]
  }
}

# Protections are the kind of thing that gets switched off for an afternoon and
# left off for a year. A check block reports on every plan without blocking
# one, which is the right weight for it: during a migration the warning is
# expected, and on any other day it means somebody forgot.
check "protections_are_on" {
  assert {
    condition = (
      hcloud_server.prod.delete_protection &&
      hcloud_server.prod.rebuild_protection
    )
    error_message = "${var.server_name}: delete or rebuild protection is off. If a replacement just finished, re-apply with the defaults. If one is in flight, ignore this."
  }
}
