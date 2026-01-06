#!/usr/bin/env bash
set -euo pipefail

SLUG="wikidata"
CFG_PATH="$(pwd)/Qleverfile-ui-wikidata.yml"
CNAME="qlever.ui.MPIEBKG"

if [[ -z "$SLUG" || -z "$CFG_PATH" ]]; then
  echo "Usage: $0 <slug> <config-yaml> [container_name]" >&2
  exit 2
fi

if [[ ! -f "$CFG_PATH" ]]; then
  echo "❌ Config YAML not found: $CFG_PATH" >&2
  exit 2
fi

# Copy YAML into container (to /app/db) if it’s not already there
BASENAME="$(basename "$CFG_PATH")"
docker cp "$CFG_PATH" "$CNAME:/app/db/$BASENAME"

echo "🧱 Ensuring backend row exists ($SLUG)..."
docker exec "$CNAME" bash -lc "/env/bin/python manage.py shell -c '
from backend.models import Backend
Backend.objects.get_or_create(name=\"$SLUG\", slug=\"$SLUG\")
print(\"✅ ensured backend $SLUG\")
'"

echo "Applying config for '$SLUG' from '$BASENAME'..."
docker exec "$CNAME" bash -lc "/env/bin/python manage.py config \"$SLUG\" \"/app/db/$BASENAME\""

echo "✅ Added backend '$SLUG'"

