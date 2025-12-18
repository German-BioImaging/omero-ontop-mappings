#!/usr/bin/env bash
set -euo pipefail
# manual start script for "qlever start"
# the index data is expected to be in ./index_output/ after using index_ome_data.sh
# --- Configuration ------------------------------------------------------------
#Directory where this script is executed (qlever/ subdirectory)
QLEVER_DIR="$(pwd)"
# Parent directory is the deployment folder (e.g. ome_instance/)
DEPLOY_DIR="$(dirname "$QLEVER_DIR")"
# Use the deployment folder name (PREFIX) as the instance name
INSTANCE_NAME="$(basename "$DEPLOY_DIR")"
# Directory that contains the index files
INDEX_DIR="${QLEVER_DIR}/index_output"

PORT="8888"
TOKEN="_eqIrM740XtRq"
CONTAINER_NAME="qlever.server.${INSTANCE_NAME}"
IMAGE="docker.io/adfreiburg/qlever:latest"

LOG_FILE="index_output/${INSTANCE_NAME}.server-log.txt"

# --- Commands -----------------------------------------------------------------
start_server() {
  echo "🚀 Starting QLever server for $INSTANCE_NAME..."

  # Ensure index directory exists
  if [ ! -d "$INDEX_DIR" ]; then
    echo "❌ Index directory not found: $INDEX_DIR"
    echo "Make sure you have run the indexing script first."
    exit 1
  fi

  # Ensure required index file exists
  if [ ! -f "${INDEX_DIR}/${INSTANCE_NAME}.meta-data.json" ]; then
    echo "❌ Missing index metadata file: ${INDEX_DIR}/${INSTANCE_NAME}.meta-data.json"
    echo "Did the reindexing script complete successfully?"
    exit 1
  fi

  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

  docker run -d \
    --restart=unless-stopped \
    -u "$(id -u):$(id -g)" \
    -v /etc/localtime:/etc/localtime:ro \
    -v "$INDEX_DIR":/index \
    -w /index \
    -p ${PORT}:${PORT} \
    --name "$CONTAINER_NAME" --init \
    --entrypoint bash "$IMAGE" -c "
      ServerMain \
        -i ${INSTANCE_NAME} \
        -j 4 \
        -p ${PORT} \
        -m 18G \
        -c 1G \
        -e 16G \
        -k 200 \
        -s 30s \
        -a ${TOKEN} \
        > ${INSTANCE_NAME}.server-log.txt 2>&1
    "

  echo "✅ QLever server started on: http://localhost:${PORT}/"
  echo "📄 Log file: ${LOG_FILE}"
}

stop_server() {
  echo "🛑 Stopping QLever server..."
  if docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1; then
    echo "✅ QLever server stopped."
  else
    echo "ℹ️  QLever server was not running."
  fi
}

status_server() {
  echo "📡 Checking QLever server status..."
  if docker ps --filter "name=$CONTAINER_NAME" --format '{{.Names}}' | grep -q "$CONTAINER_NAME"; then
    echo "🟢 Server is running: container $CONTAINER_NAME"
  else
    echo "🔴 Server is NOT running."
  fi
}

restart_server() {
  stop_server
  sleep 1
  start_server
}

# --- Entry Point --------------------------------------------------------------
CMD="${1:-start}"

case "$CMD" in
  start)
    start_server
    ;;
  stop)
    stop_server
    ;;
  restart)
    restart_server
    ;;
  status)
    status_server
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac
