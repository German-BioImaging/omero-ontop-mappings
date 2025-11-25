#!/usr/bin/env bash
set -euo pipefail

# Manual indexing script for OME data with QLever
# source data is expected to be in ../materialized_data.ttl
# index output will be stored in ./index_output/
# --- Basic configuration ------------------------------------------------------
# Directory where this script is executed (should be the qlever/ subdir)
QLEVER_DIR="$(pwd)"

# Parent directory is the deployment folder (e.g. ome_instance/)
DEPLOY_DIR="$(dirname "$QLEVER_DIR")"

# Use the deployment folder name as instance name (PREFIX)
INSTANCE_NAME="$(basename "$DEPLOY_DIR")"

# Default location of the materialized RDF: in the deployment dir
DEFAULT_DATA_FILE="${DEPLOY_DIR}/materialized_data.ttl"

# Optional CLI override:
#   ./reindex_ome_data.sh [path/to/materialized.ttl] [graph-uri]
USER_DATA_FILE="${1:-}"
USER_GRAPH_URI="${2:-}"

# --- Resolve data file (interactive) -----------------------------------------

# Start from CLI arg if provided otherwise from default
if [[ -n "$USER_DATA_FILE" ]]; then
  DATA_FILE="$USER_DATA_FILE"
else
  DATA_FILE="$DEFAULT_DATA_FILE"
fi

echo "📄 Detected materialized RDF file:"
echo "    $DATA_FILE"
echo ""

while true; do
  read -r -p "Use this file? [yes]/no: " CONFIRM
  CONFIRM=${CONFIRM:-yes}
  CONFIRM_LC=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')

  case "$CONFIRM_LC" in
    yes|y)
      # Confirm current DATA_FILE; if invalid, immediately ask for a new one
      if [[ ! -s "$DATA_FILE" ]]; then
        echo "❌ File does not exist or is empty: $DATA_FILE"
        echo ""
        echo "Please enter the full path to the materialized TTL file:"
        read -r NEW_FILE

        if [[ -z "$NEW_FILE" ]]; then
          echo "❌ No file provided. Aborting."
          exit 1
        fi

        DATA_FILE="$NEW_FILE"

        if [[ ! -s "$DATA_FILE" ]]; then
          echo "❌ File does not exist or is empty: $DATA_FILE"
          echo ""
          # loop again, asking yes/no for the new DATA_FILE
          continue
        fi
      fi
      # DATA_FILE is valid
      break
      ;;
    no|n)
      echo "Please enter the full path to the materialized TTL file:"
      read -r NEW_FILE

      if [[ -z "$NEW_FILE" ]]; then
        echo "❌ No file provided. Aborting."
        exit 1
      fi

      DATA_FILE="$NEW_FILE"

      if [[ ! -s "$DATA_FILE" ]]; then
        echo "❌ File does not exist or is empty: $DATA_FILE"
        echo ""
        # ask again (yes/no for this new DATA_FILE)
        continue
      fi

      # DATA_FILE is valid; no need to reconfirm again
      break
      ;;
    *)
      echo "Please answer yes or no."
      ;;
  esac
done

echo ""
echo "⚙️ Using materialized RDF file:"
echo "   $DATA_FILE"
echo ""

# --- Resolve graph URI. From mapping  .OBDA file  -----------------------------

# Try to infer graph URI (site URI) from the OBDA file in the deployment dir
OBDA_FILE="${DEPLOY_DIR}/${INSTANCE_NAME}.obda"
INFERRED_GRAPH_URI=""

if [[ -f "$OBDA_FILE" ]]; then
  #Find prefix line:
  #   INSTANCE_NAME: <https://example.org/site/>
  INFERRED_GRAPH_URI="$(
    grep -E "^[[:space:]]*${INSTANCE_NAME}:[[:space:]]*<" "$OBDA_FILE" 2>/dev/null \
      | head -n1 \
      | sed -E 's/.*<([^>]+)>.*/\1/'
  )" || true
fi

# Default graph URI choice:
# 1) CLI argument if provided
# 2) inferred from OBDA
# 3) fallback  (user will still be asked to confirm)
if [[ -n "$USER_GRAPH_URI" ]]; then
  GRAPH_URI="$USER_GRAPH_URI"
elif [[ -n "$INFERRED_GRAPH_URI" ]]; then
  GRAPH_URI="$INFERRED_GRAPH_URI"
else
  GRAPH_URI="http://example.org/site"
fi

echo "🌐 Detected graph URI for QLever:"
if [[ -n "$INFERRED_GRAPH_URI" ]]; then
  echo "    (from OBDA prefix ${INSTANCE_NAME}: )"
fi
echo "    $GRAPH_URI"
echo ""

while true; do
  read -r -p "Use this graph URI? [yes]/no: " CONFIRM_G
  CONFIRM_G=${CONFIRM_G:-yes}
  CONFIRM_G_LC=$(echo "$CONFIRM_G" | tr '[:upper:]' '[:lower:]')

  case "$CONFIRM_G_LC" in
    yes|y)
      break
      ;;
    no|n)
      echo "Please enter the graph URI to use (e.g. the site URI you configured):"
      read -r NEW_GRAPH_URI

      if [[ -z "$NEW_GRAPH_URI" ]]; then
        echo "❌ No graph URI provided. Aborting."
        exit 1
      fi

      GRAPH_URI="$NEW_GRAPH_URI"
      break
      ;;
    *)
      echo "Please answer yes or no."
      ;;
  esac
done

echo ""
echo "⚙️ Using graph URI:"
echo "   $GRAPH_URI"
echo ""

# --- Output & settings --------------------------------------------------------

OUTPUT_DIR="${QLEVER_DIR}/index_output"
mkdir -p "$OUTPUT_DIR"

SETTINGS_FILE="${QLEVER_DIR}/${INSTANCE_NAME}.settings.json"
LOG_FILE="${OUTPUT_DIR}/${INSTANCE_NAME}.index-log.txt"

STXXL_MEMORY="20G"
DOCKER_MEMORY="32g"

DATA_FILE_BASENAME="$(basename "$DATA_FILE")"
DATA_FILE_DIR="$(dirname "$DATA_FILE")"
DATA_FILE_IN_C="/data/${DATA_FILE_BASENAME}"

echo "⚙️ Writing settings to $SETTINGS_FILE"
echo '{ "num-triples-per-batch": 20000 }' > "$SETTINGS_FILE"

# --- Run QLever IndexBuilder --------------------------------------------------

echo ""
echo "🚀 Starting QLever index build for $INSTANCE_NAME..."
docker run --rm \
  --memory="$DOCKER_MEMORY" --memory-swap="$DOCKER_MEMORY" \
  -u "$(id -u):$(id -g)" \
  -v /etc/localtime:/etc/localtime:ro \
  -v "$QLEVER_DIR":/index \
  -v "$DATA_FILE_DIR":/data \
  -v "$OUTPUT_DIR":/index_output \
  -w /index_output \
  --name "qlever.index.${INSTANCE_NAME}" --init \
  --entrypoint bash docker.io/adfreiburg/qlever:latest -c "
    set -euo pipefail
    ulimit -Sn 500000
    IndexBuilderMain \
      -i ${INSTANCE_NAME} \
      -s /index/${INSTANCE_NAME}.settings.json \
      --vocabulary-type on-disk-compressed \
      -f '${DATA_FILE_IN_C}' \
      -g '${GRAPH_URI}' \
      -F ttl -p false \
      --stxxl-memory ${STXXL_MEMORY}
  " | tee "$LOG_FILE"

echo ""
echo "✅ Index build complete. Output stored in: $OUTPUT_DIR"
echo "📄 Log saved to: $LOG_FILE"