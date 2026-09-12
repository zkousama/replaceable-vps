#!/usr/bin/env bash
#
# Waits for a Hetzner server type to become orderable in one of the locations
# you would accept, and tells you once when it does.
#
# This exists because "sold out" is a real answer from a cloud provider, and
# there is no announcement when it stops being true. The new-generation types
# in particular spend weeks in limited availability, so a migration that
# depends on one is a migration that waits.
#
# Usage:
#   HCLOUD_TOKEN=... NTFY_URL=https://ntfy.sh/<topic> \
#     ./wait-for-capacity.sh --type cx33 --locations nbg1,hel1
#
# From cron:
#   */30 * * * * HCLOUD_TOKEN=... NTFY_URL=... /usr/local/bin/wait-for-capacity.sh --type cx33 --locations nbg1,hel1 >> /var/log/capacity.log 2>&1
#
# Exit status is 0 whether or not there is capacity: "not yet" is an answer
# rather than a failure. Only a broken run exits 1 (a missing token, an API
# error, an unknown type), so cron mail means something actually went wrong.
set -euo pipefail

TYPE=""
LOCATIONS=""
STATE_FILE="${STATE_FILE:-/var/lib/wait-for-capacity/last-state}"
NTFY_URL="${NTFY_URL:-}"

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed 's/^# \?//;$d'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --type) TYPE="${2:?--type needs a value}"; shift 2 ;;
    --locations) LOCATIONS="${2:?--locations needs a value}"; shift 2 ;;
    --state-file) STATE_FILE="${2:?--state-file needs a value}"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "unknown argument: $1" >&2; usage 64 ;;
  esac
done

[ -n "$TYPE" ] || { echo "error: --type is required" >&2; usage 64; }
[ -n "$LOCATIONS" ] || { echo "error: --locations is required" >&2; usage 64; }
[ -n "${HCLOUD_TOKEN:-}" ] || { echo "error: HCLOUD_TOKEN is not set" >&2; exit 1; }

# The response goes into a variable rather than straight down a pipe, so a
# rejected token is reported as a rejected token. Piping curl into a parser
# turns an expired credential into a JSON traceback, which is a bad way to
# find out from cron at 4am.
api() {
  local body
  if ! body=$(curl -fsSL -H "Authorization: Bearer $HCLOUD_TOKEN" \
      "https://api.hetzner.cloud/v1/$1"); then
    echo "error: the Hetzner API refused /$1: expired or revoked token?" >&2
    return 1
  fi
  printf '%s' "$body"
}

# python3 rather than jq: this runs from cron on a server, and python3 is on
# the base image while jq is a package somebody has to remember to install.
# Both filters read stdin and print one line.
types_json=$(api "server_types?name=$TYPE")
type_id=$(printf '%s' "$types_json" | python3 -c '
import json, sys
types = json.load(sys.stdin)["server_types"]
print(types[0]["id"] if types else "")
')
[ -n "$type_id" ] || { echo "error: no server type named $TYPE" >&2; exit 1; }

# One request for every datacentre, then filter locally. Asking about a
# location gets you its datacentres; asking about a datacentre gets you what
# it can actually sell today.
datacenters_json=$(api "datacenters")
available=$(
  printf '%s' "$datacenters_json" | python3 -c '
import json, sys
type_id, locations = int(sys.argv[1]), sys.argv[2].split(",")
print(",".join(
    dc["name"]
    for dc in json.load(sys.stdin)["datacenters"]
    if dc["location"]["name"] in locations
    and type_id in dc["server_types"]["available"]
))
' "$type_id" "$LOCATIONS"
)

state="unavailable"
[ -z "$available" ] || state="available"

mkdir -p "$(dirname "$STATE_FILE")"
prior="unavailable"
[ ! -f "$STATE_FILE" ] || prior=$(cat "$STATE_FILE")
printf '%s\n' "$state" > "$STATE_FILE"

stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Only the transition notifies. A check that fires on the state instead sends
# a push every time cron runs once the answer turns good, and an alert channel
# that repeats itself is one you stop reading right before it says something
# you need.
if [ "$state" = "available" ] && [ "$prior" != "available" ]; then
  echo "$stamp $TYPE is available in: $available"
  if [ -n "$NTFY_URL" ]; then
    curl -fsSL \
      -H "Title: $TYPE is available" \
      -H "Priority: 4" \
      -d "Capacity in: $available" \
      "$NTFY_URL" > /dev/null
  fi
elif [ "$state" = "available" ]; then
  echo "$stamp $TYPE still available in: $available (already notified)"
else
  echo "$stamp $TYPE unavailable in $LOCATIONS"
fi
