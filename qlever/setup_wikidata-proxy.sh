#!/usr/bin/env bash
set -euo pipefail

# --- Settings (override via env if you like) ---------------------------------
PROXY_NAME="${PROXY_NAME:-wikidata-proxy}"
PROXY_PORT="${PROXY_PORT:-8890}"   # host port → container :80

# --- Paths (relative to where you run this script) ---------------------------
ROOT_DIR="$(pwd)"
PROXY_DIR="${ROOT_DIR}/wikidata-proxy"
CONF_DIR="${PROXY_DIR}/conf.d"
CONF_FILE="${CONF_DIR}/default.conf"

echo "→ Creating nginx config at: ${CONF_FILE}"
mkdir -p "${CONF_DIR}"

# Write default.conf (idempotent overwrite)
cat > "${CONF_FILE}" <<'NGINX'
# Nginx proxy for Wikidata QLever API
# Avoid duplicate CORS headers: only allow methods/headers, not origin.

server {
  listen 80;

  location / {
    # Preflight: just return 204, no headers here
    if ($request_method = OPTIONS) {
      return 204;
    }

    # Upstream to Freiburg
    resolver 1.1.1.1 8.8.8.8 ipv6=off;
    proxy_ssl_server_name on;
    proxy_pass https://qlever.dev/api/wikidata;

    # CORS headers (keep out of the IF, so Nginx accepts them)
    add_header Access-Control-Allow-Methods "GET, POST, OPTIONS" always;
    add_header Access-Control-Allow-Headers "*" always;

    # IMPORTANT: do NOT set Access-Control-Allow-Origin here,
    # to avoid “Multiple CORS header ‘Access-Control-Allow-Origin’ not allowed”.
  }
}
NGINX


# --- Run (or re-run) the container ------------------------------------------
echo "→ Starting docker container '${PROXY_NAME}' on port ${PROXY_PORT} ..."
docker rm -f "${PROXY_NAME}" >/dev/null 2>&1 || true
docker pull -q nginx:alpine >/dev/null 2>&1 || true

docker run -d \
  --name "${PROXY_NAME}" \
  -p "${PROXY_PORT}:80" \
  -v "${CONF_DIR}:/etc/nginx/conf.d:ro" \
  --restart unless-stopped \
  nginx:alpine >/dev/null

echo "Proxy is up."

