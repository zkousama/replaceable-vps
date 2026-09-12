# The point of the whole repository is in these 2 resources.
#
# `content` here is an expression rather than a literal address. That makes
# every record a dependent of the server in one graph, so replacing the server
# is the entire instruction for a cutover: the records re-evaluate on the way
# out of the same apply, and there's no list of names to go and edit by hand.
#
# Write an address in here as a literal and you get the other version of this
# job, which is a checklist, a console, and a record you miss.

resource "cloudflare_record" "a" {
  for_each = toset(var.a_records)

  zone_id = var.cloudflare_zone_id
  name    = each.value
  type    = "A"
  content = hcloud_server.prod.ipv4_address
  proxied = var.proxied

  # 1 means automatic. A proxied record accepts nothing else.
  ttl = var.proxied ? 1 : 300
}

resource "cloudflare_record" "aaaa" {
  for_each = toset(var.aaaa_records)

  zone_id = var.cloudflare_zone_id
  name    = each.value
  type    = "AAAA"
  content = hcloud_server.prod.ipv6_address
  proxied = var.proxied
  ttl     = var.proxied ? 1 : 300
}
