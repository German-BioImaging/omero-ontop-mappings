#!/usr/bin/env bash
set -euo pipefail
# Manual launch script for "qlever-ui" with MPIEBKG backend in Docker
# Use current directory as the instance
INSTANCE_DIR="$(pwd)"
CNAME="qlever.ui.MPIEBKG"
IMAGE="docker.io/adfreiburg/qlever-ui:latest"
PORT="8176"

DB_FILE="$INSTANCE_DIR/MPIEBKG.ui-db.sqlite3"
CFG_MAIN="$INSTANCE_DIR/Qleverfile-ui.yml"
EXAMPLES_JSON="$INSTANCE_DIR/examples.json"

# Override of Django templates and static files
BRAND_DIR="$INSTANCE_DIR/branding"
FAVICON="$BRAND_DIR/favicon.ico"
STYLE="$BRAND_DIR/style.css"
LOGO_SVG="$BRAND_DIR/LOGO.svg"
LOGO_PNG="$BRAND_DIR/logo2.png"
TPL_HEAD="$BRAND_DIR/head.html"
TPL_HEADER="$BRAND_DIR/header.html"
TPL_FOOTER="$BRAND_DIR/footer.html"

run_exec() {
  docker exec "$CNAME" bash -lc "$*"
}

case "${1:-start}" in
  start)
    echo "🟢 Starting qlever-ui..."
    docker rm -f "$CNAME" >/dev/null 2>&1 || true
    
    # Edit Qleverfile-ui.yml
    ### Ensure baseUrl is not localhost when deploy on a server
    UI_CFG="$CFG_MAIN"

    CURRENT_BASEURL="$(grep -E '^[[:space:]]*baseUrl:' "$UI_CFG" | awk '{print $2}')"
    HOSTNAME_DETECTED="$(hostname -f 2>/dev/null || hostname)"

    if [[ "$CURRENT_BASEURL" == "http://localhost:8888" || "$CURRENT_BASEURL" == "http://127.0.0.1:8888" ]]; then
      echo "Default qlever-ui is configured to use localhost."
      echo
      echo "Detected this host name:"
      echo "  $HOSTNAME_DETECTED"
      echo
      echo "Choose baseUrl is launching in a live server:"
      echo "  1) Keep localhost"
      echo "  2) Use hostname"
      read -rp "Select [1-2] (default 1): " choice
      choice="${choice:-1}"

      if [[ "$choice" == "2" ]]; then
        NEW_BASEURL="http://${HOSTNAME_DETECTED}:8888"
        sed -i.bak -E "s|^[[:space:]]*baseUrl:.*|    baseUrl: ${NEW_BASEURL}|" "$UI_CFG" \
        && rm -f "${UI_CFG}.bak"
        echo "✅ baseUrl updated to use hostname"
      else
        echo "ℹ️  Keeping baseUrl as localhost"
      fi
    fi

    ###

    # Base mounts
    RUN_ARGS="--name $CNAME -p ${PORT}:7000 -v \"$INSTANCE_DIR\":/app/db -e QLEVERUI_DATABASE_URL=sqlite:////app/db/$(basename "$DB_FILE")"
    # Branding overrides
    [ -f "$FAVICON" ]    && RUN_ARGS="$RUN_ARGS -v \"$FAVICON\":/app/backend/static/favicon.ico:ro"
    [ -f "$STYLE" ]      && RUN_ARGS="$RUN_ARGS -v \"$STYLE\":/app/backend/static/css/style.css:ro"
    [ -f "$LOGO_SVG" ]   && RUN_ARGS="$RUN_ARGS -v \"$LOGO_SVG\":/app/backend/static/img/LOGO.svg:ro"
    [ -f "$LOGO_PNG" ]   && RUN_ARGS="$RUN_ARGS -v \"$LOGO_PNG\":/app/backend/static/img/logo2.png:ro"
    [ -f "$TPL_HEAD" ]   && RUN_ARGS="$RUN_ARGS -v \"$TPL_HEAD\":/app/backend/templates/partials/head.html:ro"
    [ -f "$TPL_HEADER" ] && RUN_ARGS="$RUN_ARGS -v \"$TPL_HEADER\":/app/backend/templates/partials/header.html:ro"
    [ -f "$TPL_FOOTER" ] && RUN_ARGS="$RUN_ARGS -v \"$TPL_FOOTER\":/app/backend/templates/partials/footer.html:ro"

    # Start container
    eval docker run -d $RUN_ARGS "$IMAGE"

    echo "⏳ Waiting for Django to initialize..."
    sleep 5

    echo "⚙️  Running migrations..."
    run_exec "/env/bin/python manage.py migrate --noinput >/dev/null 2>&1 || true"

    echo "🧱 Ensuring backend (mpiebkg) exists ..."
    run_exec "/env/bin/python manage.py shell -c '
from backend.models import Backend
Backend.objects.get_or_create(name=\"mpiebkg\", slug=\"mpiebkg\")
print(\"✅ ensured backend mpiebkg\")
'"

    if [ -f "$CFG_MAIN" ]; then
      echo "🔧 Applying config from $(basename "$CFG_MAIN")"
      run_exec "/env/bin/python manage.py config mpiebkg /app/db/$(basename "$CFG_MAIN") --hide-all-other-backends || true"
    else
      echo "⚠️  Skipping backend config (missing $CFG_MAIN)"
    fi

    if [ -f "$EXAMPLES_JSON" ]; then
      echo "📚 Importing examples from $(basename "$EXAMPLES_JSON")..."
      run_exec "/env/bin/python manage.py shell <<'PY'
import json, sys, pathlib
from django.db import transaction
from backend.models import Backend, Example

p = pathlib.Path('/app/db/examples.json')
try:
    data = json.loads(p.read_text(encoding='utf-8'))
except Exception as e:
    print(f'[ERROR] Could not read/parse examples.json: {e}', file=sys.stderr)
    sys.exit(1)

def find_backend(identifier):
    try:
        return Backend.objects.get(slug=identifier)
    except Backend.DoesNotExist:
        try:
            return Backend.objects.get(name=identifier)
        except Backend.DoesNotExist:
            return None

created = updated = skipped = 0
with transaction.atomic():
    for item in data:
        bkey = item.get('backend') or item.get('slug') or 'mpiebkg'
        name = item.get('name')
        query = item.get('query')
        if not name or not query:
            skipped += 1
            continue
        be = find_backend(bkey)
        if be is None:
            skipped += 1
            continue
        obj, was_created = Example.objects.update_or_create(
            backend=be, name=name, defaults={'query': query}
        )
        created += was_created
        updated += (not was_created)
print(f'Examples applied: created={created}, updated={updated}, skipped={skipped}')
PY"
    else
      echo "ℹ️  No examples.json found — skipping examples import."
    fi

    # Determine URL to show to the user
    UI_HOST="localhost"
    if [[ "${choice:-1}" == "2" ]]; then
    UI_HOST="$HOSTNAME_DETECTED"
    fi

    # Read the backend URL from the config (what the UI will call)
    FINAL_BASEURL="$(awk '/^[[:space:]]*baseUrl:/{print $2; exit}' "$UI_CFG")"

    echo "✅ qlever-ui started:"
    echo "   UI:      http://${UI_HOST}:${PORT}/mpiebkg"
    echo "   Backend: ${FINAL_BASEURL}" 
    ;;

  stop)
    echo "🛑 Stopping qlever-ui..."
    docker rm -f "$CNAME" >/dev/null 2>&1 || true
    echo "✅ qlever-ui stopped."
    ;;

  status)
    docker ps --filter "name=$CNAME"
    ;;

  restart)
    "$0" stop
    "$0" start
    ;;

  *)
    echo "Usage: $0 {start|stop|status|restart}" >&2
    exit 1
    ;;
esac
