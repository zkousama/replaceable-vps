output "ipv4" {
  value = hcloud_server.prod.ipv4_address
}

output "ipv6" {
  value = hcloud_server.prod.ipv6_address
}

output "server_id" {
  value = hcloud_server.prod.id
}

# The 2 that answer "did the replacement actually do what I asked", which is
# the question at the end of the runbook.
output "server_type" {
  value = hcloud_server.prod.server_type
}

output "location" {
  value = hcloud_server.prod.location
}

# Written for the Ansible inventory rather than for reading. The playbook needs
# an address and a port, and copying them by hand is how they go stale.
output "inventory_line" {
  value = "${var.server_name} ansible_host=${hcloud_server.prod.ipv4_address} ansible_port=${var.ssh_port}"
}
