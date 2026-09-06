#!/bin/zsh
set -euo pipefail

# Creates a CPU Serverless AI endpoint for the PortalOS phone demo.
# Requires: nebius CLI profile, Token Factory key in ../backend/.env
# Does not use a GPU preset.

export PATH="$HOME/.nebius/bin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PARENT_ID="${NEBIUS_PARENT_ID:-project-u00rc5kzkc00stzgz2y0p6}"
NAME="${NEBIUS_ENDPOINT_NAME:-portalsos-demo}"

if [ -f "$ROOT/backend/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/backend/.env"
  set +a
fi

if [ -z "${NEBIUS_API_KEY:-}" ]; then
  echo "NEBIUS_API_KEY is missing" >&2
  exit 1
fi

SUBNET_ID="${NEBIUS_SUBNET_ID:-}"
if [ -z "$SUBNET_ID" ]; then
  SUBNET_ID="$(nebius vpc subnet list --parent-id "$PARENT_ID" --format jsonpath='{$.items[0].metadata.id}' 2>/dev/null || true)"
fi
if [ -z "$SUBNET_ID" ]; then
  echo "Could not resolve a VPC subnet. Set NEBIUS_SUBNET_ID." >&2
  exit 1
fi

echo "Using subnet $SUBNET_ID"

# Public node image + injected demo files. Auth none so the demo page is open.
nebius ai endpoint create \
  --name "$NAME" \
  --parent-id "$PARENT_ID" \
  --image docker.io/library/node:22-alpine \
  --platform cpu-d3 \
  --preset 4vcpu-16gb \
  --disk-size 50Gi \
  --preemptible \
  --container-port 8080 \
  --working-dir /app \
  --container-command node \
  --args /app/server.js \
  --inject-file "$ROOT/backend/server.js:/app/server.js" \
  --inject-file "$ROOT/web/index.html:/app/web/index.html" \
  --inject-file "$ROOT/web/styles.css:/app/web/styles.css" \
  --inject-file "$ROOT/web/app.js:/app/web/app.js" \
  --env "NEBIUS_API_KEY=${NEBIUS_API_KEY}" \
  --env "NEBIUS_MODEL=${NEBIUS_MODEL:-nvidia/Nemotron-3_5-Lightning}" \
  --env PORT=8080 \
  --subnet-id "$SUBNET_ID" \
  --auth none

echo "Waiting for public HTTPS..."
for i in $(seq 1 60); do
  URL="$(nebius ai endpoint get-by-name --name "$NAME" --parent-id "$PARENT_ID" --format json 2>/dev/null \
    | python3 -c "import sys,json
d=json.load(sys.stdin)
eps=(d.get('status') or {}).get('public_endpoints') or (d.get('status') or {}).get('publicEndpoints') or []
https=[e for e in eps if str(e).startswith('https://')]
print(https[0] if https else '')" || true)"
  if [ -n "$URL" ]; then
    echo "MANAGED_HTTPS=$URL"
    exit 0
  fi
  sleep 10
done

echo "Endpoint created but HTTPS URL not visible yet. Check the Nebius console." >&2
nebius ai endpoint get-by-name --name "$NAME" --parent-id "$PARENT_ID" --format json
exit 2
