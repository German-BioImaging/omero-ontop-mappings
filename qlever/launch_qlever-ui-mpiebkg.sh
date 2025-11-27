#!/usr/bin/env bash
set -euo pipefail
# Manual launch script for "qlever-ui" with MPIEBKG backend in Docker

# Use current directory as the qlever instance dir
INSTANCE_DIR="$(pwd)"

# Parent directory is the deployment folder (same as PREFIX, e.g. ome_instance/)
DEPLOY_DIR="$(dirname "$INSTANCE_DIR")"

# Deployment instance name (PREFIX)
INSTANCE_NAME="$(basename "$DEPLOY_DIR")"

CNAME="qlever.ui.MPIEBKG"
IMAGE="docker.io/adfreiburg/qlever-ui:latest"
PORT="8176"

# Make DB name consistent with the deployment instance name
DB_FILE="$INSTANCE_DIR/${INSTANCE_NAME}.ui-db.sqlite3"

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

    echo "✅ qlever-ui started at http://localhost:${PORT}/mpiebkg"
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
