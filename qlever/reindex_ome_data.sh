#!/usr/bin/env bash
set -euo pipefail
# Manual indexing script for OME data
# source data is expected to be in ../materialize/materialized-ome.ttl
# index output will be stored in ./index_output/
# --- Configuration ------------------------------------------------------------
INSTANCE_DIR="$(pwd)"
INSTANCE_NAME="MPIEBKG"

# Directory where the materialized file lives (one level up, in materialize/)
MATERIALIZE_DIR="$(cd "${INSTANCE_DIR}/../materialize" && pwd)"
# Input file now outside the root directory
DATA_FILE="${MATERIALIZE_DIR}/materialized-ome.ttl"
# Output directory inside root
OUTPUT_DIR="${INSTANCE_DIR}/index_output"
mkdir -p "$OUTPUT_DIR"

SETTINGS_FILE="${INSTANCE_DIR}/${INSTANCE_NAME}.settings.json"
LOG_FILE="${OUTPUT_DIR}/${INSTANCE_NAME}.index-log.txt"

STXXL_MEMORY="20G"
DOCKER_MEMORY="32g"

# Path to the data file inside the container
DATA_FILE_IN_C="/materialize/materialized-ome.ttl"

# --- Pre-flight ---------------------------------------------------------------
[[ -s "$DATA_FILE" ]] || { echo "❌ Missing or empty file: $DATA_FILE"; exit 1; }
echo "⚙️  Writing settings to $SETTINGS_FILE"
echo '{ "num-triples-per-batch": 20000 }' > "$SETTINGS_FILE"

# --- Run QLever IndexBuilder --------------------------------------------------
echo "🚀 Starting QLever index build for $INSTANCE_NAME..."
docker run --rm \
  --memory="$DOCKER_MEMORY" --memory-swap="$DOCKER_MEMORY" \
  -u "$(id -u):$(id -g)" \
  -v /etc/localtime:/etc/localtime:ro \
  -v "$INSTANCE_DIR":/index \
  -v "$MATERIALIZE_DIR":/materialize \
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
      -g http://lod.evolbio.mpg.de/ome \
      -F ttl -p false \
      --stxxl-memory ${STXXL_MEMORY}
  " | tee "$LOG_FILE"

echo "✅ Index build complete. Output stored in: $OUTPUT_DIR"
echo "📄 Log saved to: $LOG_FILE"