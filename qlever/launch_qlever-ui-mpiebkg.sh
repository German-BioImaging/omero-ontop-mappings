#!/usr/bin/env bash
set -euo pipefail

# --- Paths / Instance ---------------------------------------------------------
INSTANCE_DIR="$(pwd)"
DEPLOY_DIR="$(dirname "$INSTANCE_DIR")"
INSTANCE_NAME="$(basename "$DEPLOY_DIR")"

CNAME="qlever.ui.MPIEBKG"
IMAGE="docker.io/adfreiburg/qlever-ui:latest"
PORT="8176"

DB_FILE="$INSTANCE_DIR/${INSTANCE_NAME}.ui-db.sqlite3"
CFG_MAIN="$INSTANCE_DIR/Qleverfile-ui.yml"
EXAMPLES_JSON="$INSTANCE_DIR/examples.json"

BRAND_DIR="$INSTANCE_DIR/branding"
FAVICON="$BRAND_DIR/favicon.ico"
STYLE="$BRAND_DIR/style.css"
LOGO_SVG="$BRAND_DIR/LOGO.svg"
LOGO_PNG="$BRAND_DIR/logo2.png"
TPL_HEAD="$BRAND_DIR/head.html"
TPL_HEADER="$BRAND_DIR/header.html"
TPL_FOOTER="$BRAND_DIR/footer.html"

run_exec() { docker exec "$CNAME" bash -lc "$*"; }

# Portable in-place sed flags (GNU vs BSD/macOS)
if sed --version >/dev/null 2>&1; then
  SED_INPLACE=(-i -E)      # GNU
else
  SED_INPLACE=(-i '' -E)   # BSD/macOS
fi

# slugify -> lowercase, non-alnum -> '-', trim '-'
slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

case "${1:-start}" in
  start)
    echo "🟢 Starting qlever-ui..."
    docker rm -f "$CNAME" >/dev/null 2>&1 || true
    [[ -f "$CFG_MAIN" ]] || { echo "❌ Missing $CFG_MAIN"; exit 1; }

    # Read current (template) values from YAML
    CURRENT_NAME="$(awk '/^[[:space:]]*name:/{print $2; exit}' "$CFG_MAIN")"
    CURRENT_SLUG="$(awk '/^[[:space:]]*slug:/{print $2; exit}' "$CFG_MAIN")"
    INSTANCE_SLUG="$(slugify "$INSTANCE_NAME")"

    echo
    echo "Instance detected:"
    echo "  • name (menu): $INSTANCE_NAME"
    echo "  • slug (URL):  $INSTANCE_SLUG"

    # If YAML already matches the instance, skip the prompt
    if [[ "$CURRENT_NAME" == "$INSTANCE_NAME" && "$CURRENT_SLUG" == "$INSTANCE_SLUG" ]]; then
      echo "ℹ️  YAML already uses the instance values → name: $INSTANCE_NAME, slug: $INSTANCE_SLUG"
      TARGET_NAME="$INSTANCE_NAME"
      TARGET_SLUG="$INSTANCE_SLUG"
    else
      echo "Use instance values or keep template?"
      echo "  1) Keep template (name: $CURRENT_NAME, slug: $CURRENT_SLUG)"
      echo "  2) Use instance (name: $INSTANCE_NAME, slug: $INSTANCE_SLUG)"
      read -rp "Select [1-2] (default 2): " choice_ns; choice_ns="${choice_ns:-2}"

      if [[ "$choice_ns" == "2" ]]; then
        TARGET_NAME="$INSTANCE_NAME"
        TARGET_SLUG="$INSTANCE_SLUG"
        # Update YAML name & slug in place (template → instance)
        sed "${SED_INPLACE[@]}" "s|^[[:space:]]*name:.*|    name: ${TARGET_NAME}|" "$CFG_MAIN"
        sed "${SED_INPLACE[@]}" "s|^[[:space:]]*slug:.*|    slug: ${TARGET_SLUG}|" "$CFG_MAIN"
      else
        TARGET_NAME="$CURRENT_NAME"
        TARGET_SLUG="$CURRENT_SLUG"
        echo "ℹ️  Keeping template name/slug → ${TARGET_NAME} / ${TARGET_SLUG}"
      fi
    fi

    # --- Optional: switch baseUrl to hostname --------------------------------
    CURRENT_BASEURL="$(awk '/^[[:space:]]*baseUrl:/{print $2; exit}' "$CFG_MAIN")"
    HOSTNAME_DETECTED="$(hostname -f 2>/dev/null || hostname)"
    if [[ "$CURRENT_BASEURL" == "http://localhost:8888" || "$CURRENT_BASEURL" == "http://127.0.0.1:8888" ]]; then
      echo
      echo "Default qlever-ui is configured to use localhost."
      echo "Detected hostname: $HOSTNAME_DETECTED"
      echo "  1) Keep localhost"
      echo "  2) Use hostname"
      read -rp "Select [1-2] (default 1): " choice_host; choice_host="${choice_host:-1}"
      if [[ "$choice_host" == "2" ]]; then
        NEW_BASEURL="http://${HOSTNAME_DETECTED}:8888"
        sed "${SED_INPLACE[@]}" "s|^[[:space:]]*baseUrl:.*|    baseUrl: ${NEW_BASEURL}|" "$CFG_MAIN"
        echo "✅ baseUrl → ${NEW_BASEURL}"
      else
        echo "ℹ️  Keeping baseUrl as localhost"
      fi
    fi

    # Base mounts
    RUN_ARGS="--name $CNAME -p ${PORT}:7000 -v \"$INSTANCE_DIR\":/app/db -e QLEVERUI_DATABASE_URL=sqlite:////app/db/$(basename "$DB_FILE")"
    [ -f "$FAVICON" ]    && RUN_ARGS="$RUN_ARGS -v \"$FAVICON\":/app/backend/static/favicon.ico:ro"
    [ -f "$STYLE" ]      && RUN_ARGS="$RUN_ARGS -v \"$STYLE\":/app/backend/static/css/style.css:ro"
    [ -f "$LOGO_SVG" ]   && RUN_ARGS="$RUN_ARGS -v \"$LOGO_SVG\":/app/backend/static/img/LOGO.svg:ro"
    [ -f "$LOGO_PNG" ]   && RUN_ARGS="$RUN_ARGS -v \"$LOGO_PNG\":/app/backend/static/img/logo2.png:ro"
    [ -f "$TPL_HEAD" ]   && RUN_ARGS="$RUN_ARGS -v \"$TPL_HEAD\":/app/backend/templates/partials/head.html:ro"
    [ -f "$TPL_HEADER" ] && RUN_ARGS="$RUN_ARGS -v \"$TPL_HEADER\":/app/backend/templates/partials/header.html:ro"
    [ -f "$TPL_FOOTER" ] && RUN_ARGS="$RUN_ARGS -v \"$TPL_FOOTER\":/app/backend/templates/partials/footer.html:ro"

    # Start container
    eval docker run -d $RUN_ARGS "$IMAGE"
    echo "⏳ Waiting for Django to initialize..."; sleep 5

    echo "⚙️  Running migrations..."
    run_exec "/env/bin/python manage.py migrate --noinput >/dev/null 2>&1 || true"

    # --- Safe upsert: prevent UNIQUE(name), then ensure row by slug ----------
    echo "🧹 De-duplicate by name and upsert backend…"
    run_exec "BACKEND_NAME='${TARGET_NAME}' BACKEND_SLUG='${TARGET_SLUG}' /env/bin/python manage.py shell <<'PY'
import os
from backend.models import Backend
name=os.environ['BACKEND_NAME']; slug=os.environ['BACKEND_SLUG']
# Remove any other rows that already use this display name
Backend.objects.filter(name=name).exclude(slug=slug).delete()
# Upsert by slug with the display name, mark default
obj, _ = Backend.objects.update_or_create(slug=slug, defaults={'name': name, 'isDefault': True})
print({'name': obj.name, 'slug': obj.slug, 'isDefault': obj.isDefault})
PY"

    # --- Apply YAML to that slug; hide others for a clean menu ----------------
    echo "🔧 Applying config from $(basename "$CFG_MAIN") to slug=${TARGET_SLUG}"
    run_exec "/env/bin/python manage.py config ${TARGET_SLUG} /app/db/$(basename "$CFG_MAIN") --hide-all-other-backends || true"

    # --- Import examples (optional) ------------------------------------------
    if [[ -f "$EXAMPLES_JSON" ]]; then
      echo "📚 Importing examples from $(basename "$EXAMPLES_JSON")…"
      run_exec "BACKEND_SLUG='${TARGET_SLUG}' /env/bin/python manage.py shell <<'PY'
import json, sys, pathlib, os
from django.db import transaction
from backend.models import Backend, Example

p = pathlib.Path('/app/db/examples.json')
try:
    data = json.loads(p.read_text(encoding='utf-8'))
except Exception as e:
    print(f'[ERROR] Could not read/parse examples.json: {e}', file=sys.stderr); sys.exit(1)

slug = os.environ.get('BACKEND_SLUG')
try:
    be = Backend.objects.get(slug=slug)
except Backend.DoesNotExist:
    print(f'[WARN] Backend slug={slug!r} not found; skipping examples.'); sys.exit(0)

created = updated = skipped = 0
with transaction.atomic():
    for item in data:
        name = item.get('name'); query = item.get('query')
        if not name or not query: skipped += 1; continue
        obj, was_created = Example.objects.update_or_create(
            backend=be, name=name, defaults={'query': query}
        )
        created += was_created; updated += (not was_created)
print(f'Examples applied: created={created}, updated={updated}, skipped={skipped}')
PY"
    else
      echo "ℹ️  No examples.json found — skipping examples import."
    fi

    UI_HOST="localhost"; [[ "${choice_host:-1}" == "2" ]] && UI_HOST="$HOSTNAME_DETECTED"
    FINAL_BASEURL="$(awk '/^[[:space:]]*baseUrl:/{print $2; exit}' "$CFG_MAIN")"
    echo "✅ qlever-ui started:"
    echo "   UI:      http://${UI_HOST}:${PORT}/${TARGET_SLUG}"
    echo "   Name:    ${TARGET_NAME}  (menu label)"
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
    "$0" stop; "$0" start
    ;;
  *)
    echo "Usage: $0 {start|stop|status|restart}" >&2; exit 1
    ;;
esac
