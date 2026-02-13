#!/usr/bin/env bash
set -Eeuo pipefail

# Materialize VKG

# Directory of this script (materialize/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Project root = parent of materialize/
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Path to ONTOP CLI binary (adjust if needed)
ONTOPBIN="$BASE_DIR/ontop-cli/ontop"

# Deployment folder name injected by cookiecutter
DEPLOY_DIR="$BASE_DIR/omeswat"

MAPPING="$DEPLOY_DIR/omeswat.obda"
ONTOLOGY="$DEPLOY_DIR/omeswat.ttl"
PROPERTIES="$DEPLOY_DIR/omeswat.properties"

OUTPUT="$SCRIPT_DIR/materialized_data.ttl"

date
"$ONTOPBIN" materialize \
  --mapping "$MAPPING" \
  --ontology "$ONTOLOGY" \
  --properties "$PROPERTIES" \
  --format turtle \
  --output "$OUTPUT"
date
