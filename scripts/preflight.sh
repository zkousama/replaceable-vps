#!/usr/bin/env bash
#
# Checks every credential against the provider that has to accept it, before
# you start something that needs all of them.
#
# The reason this is a script and not a line in a runbook: a token nobody has
# used for months is a token nobody knows is dead. The first plan that reads
# the DNS records is where a revoked key there shows up, and in a replacement
# that plan comes after the snapshot is taken and the protections are off.
#
# Usage:
#   ./preflight.sh
#
# Reads HCLOUD_TOKEN, CLOUDFLARE_API_TOKEN, AWS_ACCESS_KEY_ID and
# AWS_SECRET_ACCESS_KEY from the environment. Exits 1 if any check fails.
set -uo pipefail

fail=0

ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=1; }
skip() { printf '  skip  %s\n' "$1"; }

echo "Credentials:"

if [ -z "${HCLOUD_TOKEN:-}" ]; then
  bad "HCLOUD_TOKEN is not set"
elif curl -fsSL -o /dev/null \
    -H "Authorization: Bearer $HCLOUD_TOKEN" \
    "https://api.hetzner.cloud/v1/servers?per_page=1"; then
  ok "HCLOUD_TOKEN is accepted"
else
  bad "HCLOUD_TOKEN was rejected by the Hetzner API"
fi

if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  bad "CLOUDFLARE_API_TOKEN is not set"
elif curl -fsSL -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    "https://api.cloudflare.com/client/v4/user/tokens/verify" \
    | grep -q '"success":true'; then
  ok "CLOUDFLARE_API_TOKEN is active"
else
  # This is the one that has actually happened. Cloudflare's verify endpoint
  # answers 200 with success:false for a revoked token, so the status code
  # alone is not the check.
  bad "CLOUDFLARE_API_TOKEN was rejected or revoked"
fi

# The state backend's keys cannot be verified without a request signature, so
# what is checkable is the shape. R2 keys are 32 characters and AWS keys are
# 20, and having AWS credentials loaded when the backend is R2 fails with a
# message about key length that takes a while to recognise.
if [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then
  skip "no state-backend key in the environment"
elif [ "${#AWS_ACCESS_KEY_ID}" -eq 32 ]; then
  ok "state-backend key is R2-shaped (32 characters)"
elif [ "${#AWS_ACCESS_KEY_ID}" -eq 20 ]; then
  bad "state-backend key is AWS-shaped (20 characters): wrong credentials for an R2 backend"
else
  bad "state-backend key is ${#AWS_ACCESS_KEY_ID} characters, which is neither AWS nor R2"
fi

echo "Tools:"
for tool in tofu curl ssh python3; do
  if command -v "$tool" > /dev/null; then
    ok "$tool"
  else
    bad "$tool is not installed"
  fi
done

exit "$fail"
