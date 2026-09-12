terraform {
  required_version = ">= 1.7"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }

    # Held on 4.x. The 5.0 provider renamed cloudflare_record to
    # cloudflare_dns_record and changed how record values are written, so
    # moving is a rewrite of dns.tf rather than a version bump. Worth doing
    # deliberately, not in the middle of a migration.
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.40"
    }
  }
}

# Both providers read their credentials from the environment: HCLOUD_TOKEN and
# CLOUDFLARE_API_TOKEN. Nothing about them is declared here, so there is no
# variable anybody can accidentally set in a .tfvars file and commit.
provider "hcloud" {}
provider "cloudflare" {}
