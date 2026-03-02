#!/usr/bin/env bash
set -euo pipefail

# Unified populate script: runs either:
#  - MODE=host      -> use local `omero` CLI against localhost:14064 and ./img
#  - MODE=container -> run OMERO CLI inside docker container against localhost:4064 and /repo/img
#  - MODE=auto      -> choose container if docker compose + .omero/docker-compose.yml exist
#
# Default is host for local convenience. CI/workflow should set MODE=container explicitly.
MODE="${MODE:-host}"

# Ensure OMERO CLI never blocks on pagination in CI/non-interactive runs
export OMERO_PAGER="${OMERO_PAGER:-cat}"
# set LESS to avoid any pager issues if OMERO_PAGER is ignored for some reason (e.g. older OMERO CLI)
export LESS="${LESS:--FRSX}"

COMPOSE_FILE="${COMPOSE_FILE:-.omero/docker-compose.yml}"
SERVICE="${SERVICE:-omero}"
OMERO_BIN_IN_CONTAINER="${OMERO_BIN_IN_CONTAINER:-/opt/omero/server/OMERO.server/bin/omero}"
OMERO_BIN_HOST="${OMERO_BIN_HOST:-omero}"

USER="${OMERO_USER:-root}"
PASS="${OMERO_PASS:-omero}"

HOST_HOSTSIDE="${OMERO_HOST:-127.0.0.1}"
PORT_HOSTSIDE="${OMERO_PORT:-14064}"

HOST_IN_CONTAINER="${HOST_IN_CONTAINER:-localhost}"
PORT_IN_CONTAINER="${PORT_IN_CONTAINER:-4064}"

IMG_DIR_HOST="${IMG_DIR_HOST:-img}"
IMG_DIR_CONTAINER="${IMG_DIR_CONTAINER:-/repo/img}"

die() { echo "ERROR: $*" >&2; exit 1; }

have_docker_compose() {
  command -v docker >/dev/null 2>&1 || return 1
  docker compose version >/dev/null 2>&1 || return 1
  [ -f "$COMPOSE_FILE" ] || return 1
  return 0
}

# Optional auto-detect mode 
if [ "$MODE" = "auto" ]; then
  if have_docker_compose; then
    MODE="container"
  else
    MODE="host"
  fi
fi

# Validate MODE early to avoid running any commands if misconfigured
if [ "$MODE" != "host" ] && [ "$MODE" != "container" ]; then
  die "Invalid MODE='$MODE' (must be host|container|auto)"
fi
echo "mode:            $MODE"
echo "user:            $USER"
echo "pager:           $OMERO_PAGER  (LESS=$LESS)"

if [ "$MODE" = "container" ]; then
  echo "compose:          $COMPOSE_FILE"
  echo "service:          $SERVICE"
  echo "omero cli:        $OMERO_BIN_IN_CONTAINER"
  echo "server:           ${HOST_IN_CONTAINER}:${PORT_IN_CONTAINER} (container SSL)"
  echo "img dir:          $IMG_DIR_CONTAINER"
else
  echo "omero cli:        $OMERO_BIN_HOST"
  echo "server:           ${HOST_HOSTSIDE}:${PORT_HOSTSIDE} (host)"
  echo "img dir:          $IMG_DIR_HOST"
fi

# ---------------------------------------------------------------------
# run_omero: run exactly ONE command string (avoid $* splitting!)
# You must pass a single string that includes any needed quoting.
# ---------------------------------------------------------------------
run_omero() {
  local cmd="$1"

  if [ "$MODE" = "container" ]; then
    docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" sh -lc \
      "'$OMERO_BIN_IN_CONTAINER' -u '$USER' -w '$PASS' -s '$HOST_IN_CONTAINER' -p '$PORT_IN_CONTAINER' -C $cmd"
  else
    # Run via bash -lc so quoting inside $cmd is interpreted consistently
    bash -lc \
      "'$OMERO_BIN_HOST' -u '$USER' -w '$PASS' -s '$HOST_HOSTSIDE' -p '$PORT_HOSTSIDE' -C $cmd"
  fi
}

# ---------------------------------------------------------------------
# Basic checks (container mode)
# ---------------------------------------------------------------------
if [ "$MODE" = "container" ]; then
  docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" sh -lc "test -x '$OMERO_BIN_IN_CONTAINER' && '$OMERO_BIN_IN_CONTAINER' version" \
    || die "OMERO CLI not found/executable at $OMERO_BIN_IN_CONTAINER"

  docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" sh -lc "test -d '$IMG_DIR_CONTAINER' && ls -la '$IMG_DIR_CONTAINER' >/dev/null" \
    || die "Repo img not found at $IMG_DIR_CONTAINER (check volumes mount)"
else
  command -v "$OMERO_BIN_HOST" >/dev/null 2>&1 || die "Host OMERO CLI not found: $OMERO_BIN_HOST"
  [ -d "$IMG_DIR_HOST" ] || die "Host img dir not found: $IMG_DIR_HOST"
fi

# ---------------------------------------------------------------------
# Wait for OMERO readiness (probe login with hql)
# ---------------------------------------------------------------------
echo "Waiting for OMERO.server to accept sessions (login probe)..."
for i in $(seq 1 180); do
  if run_omero "hql 'select count(e.id) from Experimenter e'" >/dev/null 2>&1; then
    echo "OMERO is ready."
    break
  fi
  echo "  not ready yet ($i/180) ..."
  if [ "$MODE" = "container" ]; then
    docker compose -f "$COMPOSE_FILE" logs --no-color --tail=25 omero || true
  fi
  sleep 2
done

run_omero "hql 'select count(e.id) from Experimenter e'" >/dev/null 2>&1 \
  || die "OMERO never became ready"

# ---------------------------------------------------------------------
# Create 3 datasets
# IMPORTANT: keep names quoted (spaces!) -> name='Dataset 1'
# ---------------------------------------------------------------------
DS1="$(run_omero "obj new Dataset name='Dataset 1'")"
DS2="$(run_omero "obj new Dataset name='Dataset 2'")"
DS3="$(run_omero "obj new Dataset name='Dataset 3'")"
echo "Datasets: $DS1 $DS2 $DS3"

# Dataset annotations
MAP1="$(run_omero "obj new MapAnnotation ns='http://purl.org/dc/terms/'")"
run_omero "obj new DatasetAnnotationLink parent='$DS1' child='$MAP1'"
run_omero "obj map-set '$MAP1' mapValue contributor 'Test User'"
run_omero "obj map-set '$MAP1' mapValue subject 'Test images'"
run_omero "obj map-set '$MAP1' mapValue provenance 'Screenshots'"

TAG1="$(run_omero "tag create --name 'TestTag'")"
run_omero "obj new DatasetAnnotationLink parent='$DS1' child='$TAG1'"

MAP2="$(run_omero "obj new MapAnnotation ns='http://purl.org/dc/terms/'")"
# Preserve original behavior: DS2 linked to MAP1
run_omero "obj new DatasetAnnotationLink parent='$DS2' child='$MAP1'"
run_omero "obj map-set '$MAP2' mapValue contributor 'Anonymous'"
run_omero "obj map-set '$MAP2' mapValue subject 'Ontop Tutorial'"
run_omero "obj map-set '$MAP2' mapValue provenance 'Screenshots'"

MAP3="$(run_omero "obj new MapAnnotation ns='http://purl.org/dc/terms/'")"
run_omero "obj new DatasetAnnotationLink parent='$DS3' child='$MAP3'"
run_omero "obj map-set '$MAP3' mapValue contributor 'Caligula'"
run_omero "obj map-set '$MAP3' mapValue subject 'OMERO Mapping'"
run_omero "obj map-set '$MAP3' mapValue provenance 'Screenshots'"

# Project + links
PROJ="$(run_omero "obj new Project name='Project'")"
run_omero "obj new ProjectDatasetLink parent='$PROJ' child='$DS1'"
run_omero "obj new ProjectDatasetLink parent='$PROJ' child='$DS2'"
run_omero "obj new ProjectDatasetLink parent='$PROJ' child='$DS3'"

MAP4="$(run_omero "obj new MapAnnotation ns='http://purl.org/dc/terms/'")"
run_omero "obj new ProjectAnnotationLink parent='$PROJ' child='$MAP4'"
run_omero "obj map-set '$MAP4' mapValue contributor 'Nophretete'"
run_omero "obj map-set '$MAP4' mapValue subject 'OMERO Ontology'"
run_omero "obj map-set '$MAP4' mapValue provenance 'Test Data'"

# ---------------------------------------------------------------------
# Import images
# ---------------------------------------------------------------------
echo "=== Importing images ==="

if [ "$MODE" = "container" ]; then
  # do everything inside container where /repo/img exists
  docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" sh -lc "
    set -e
    IMG_DIR='$IMG_DIR_CONTAINER'
    OMERO='$OMERO_BIN_IN_CONTAINER'
    U='$USER'; P='$PASS'; S='$HOST_IN_CONTAINER'; PORT='$PORT_IN_CONTAINER'

    echo \"  14-png: \$(find \"\$IMG_DIR\" -type f -name '*_14-*.png' | wc -l)\"
    echo \"  15-png: \$(find \"\$IMG_DIR\" -type f -name '*_15-*.png' | wc -l)\"
    echo \"  16-png: \$(find \"\$IMG_DIR\" -type f -name '*_16-*.png' | wc -l)\"
    echo \"  ome.tif: \$(find \"\$IMG_DIR\" -type f -name '*.ome.tif' | wc -l)\"

    echo \"Importing *_14-*.png -> $DS1\"
    find \"\$IMG_DIR\" -type f -name '*_14-*.png' -print0 | sort -z | while IFS= read -r -d '' f; do
      \"\$OMERO\" -u \"\$U\" -w \"\$P\" -s \"\$S\" -p \"\$PORT\" -C import \"\$f\" -d '$DS1'
    done

    echo \"Importing *_15-*.png -> $DS2\"
    find \"\$IMG_DIR\" -type f -name '*_15-*.png' -print0 | sort -z | while IFS= read -r -d '' f; do
      \"\$OMERO\" -u \"\$U\" -w \"\$P\" -s \"\$S\" -p \"\$PORT\" -C import \"\$f\" -d '$DS2'
    done

    echo \"Importing *_16-*.png -> $DS3\"
    find \"\$IMG_DIR\" -type f -name '*_16-*.png' -print0 | sort -z | while IFS= read -r -d '' f; do
      \"\$OMERO\" -u \"\$U\" -w \"\$P\" -s \"\$S\" -p \"\$PORT\" -C import \"\$f\" -d '$DS3'
    done

    echo \"Importing *.ome.tif -> $DS2\"
    find \"\$IMG_DIR\" -type f -name '*.ome.tif' -print0 | sort -z | while IFS= read -r -d '' f; do
      \"\$OMERO\" -u \"\$U\" -w \"\$P\" -s \"\$S\" -p \"\$PORT\" -C import \"\$f\" -d '$DS2'
    done
  "
else
  # host: import using local filesystem ./img
  echo "  14-png: $(find "$IMG_DIR_HOST" -type f -name '*_14-*.png' | wc -l | tr -d ' ')"
  echo "  15-png: $(find "$IMG_DIR_HOST" -type f -name '*_15-*.png' | wc -l | tr -d ' ')"
  echo "  16-png: $(find "$IMG_DIR_HOST" -type f -name '*_16-*.png' | wc -l | tr -d ' ')"
  echo "  ome.tif: $(find "$IMG_DIR_HOST" -type f -name '*.ome.tif' | wc -l | tr -d ' ')"

  find "$IMG_DIR_HOST" -type f -name '*_14-*.png' -print0 | sort -z | while IFS= read -r -d '' f; do
    run_omero "import '$f' -d '$DS1'"
  done
  find "$IMG_DIR_HOST" -type f -name '*_15-*.png' -print0 | sort -z | while IFS= read -r -d '' f; do
    run_omero "import '$f' -d '$DS2'"
  done
  find "$IMG_DIR_HOST" -type f -name '*_16-*.png' -print0 | sort -z | while IFS= read -r -d '' f; do
    run_omero "import '$f' -d '$DS3'"
  done
  find "$IMG_DIR_HOST" -type f -name '*.ome.tif' -print0 | sort -z | while IFS= read -r -d '' f; do
    run_omero "import '$f' -d '$DS2'"
  done
fi

# ---------------------------------------------------------------------
# Image annotations 
# ---------------------------------------------------------------------
TAG2="$(run_omero "tag create --name 'Screenshot'")"

for image_index in $(seq 1 10); do
  ann="$(run_omero "obj new MapAnnotation ns='http://purl.org/dc/terms/'")"
  run_omero "obj new ImageAnnotationLink parent='Image:${image_index}' child='$ann'"
  run_omero "obj map-set '$ann' mapValue date '$(date)'"
  run_omero "obj map-set '$ann' mapValue contributor 'Test User'"
  run_omero "obj map-set '$ann' mapValue subject 'Unittest'"
  run_omero "obj new ImageAnnotationLink parent='Image:${image_index}' child='$TAG2'"
done

ann_no_ns="$(run_omero "obj new MapAnnotation")"
run_omero "obj new ImageAnnotationLink parent='Image:12' child='$ann_no_ns'"
run_omero "obj map-set '$ann_no_ns' mapValue annotator 'MrX'"

ann_non_uri="$(run_omero "obj new MapAnnotation ns='www.openmicroscopy.org/ns/default'")"
run_omero "obj new ImageAnnotationLink parent='Image:11' child='$ann_non_uri'"
run_omero "obj map-set '$ann_non_uri' mapValue sampletype 'screen'"

ann_issue16="$(run_omero "obj new MapAnnotation ns='hms.harvard.edu/omero/forms/kvdata/MPB Annotations/'")"
run_omero "obj new ImageAnnotationLink parent='Image:10' child='$ann_issue16'"
run_omero "obj map-set '$ann_issue16' mapValue Assay 'PRTSC'"

ann_issue17="$(run_omero "obj new MapAnnotation ns='/MouseCT/Skyscan/System'")"
run_omero "obj new ImageAnnotationLink parent='Image:9' child='$ann_issue17'"
run_omero "obj map-set '$ann_issue17' mapValue Assay 'Bruker'"

ann_special="$(run_omero "obj new MapAnnotation")"
run_omero "obj new ImageAnnotationLink parent='Image:1' child='$ann_special'"
run_omero "obj map-set '$ann_special' mapValue 'foo^bar' 'bar'"
run_omero "obj map-set '$ann_special' mapValue '\$foo*bar#ba' 'some**thing'"
run_omero "obj map-set '$ann_special' mapValue '&*foo&^bar' 'cool'"

today="$(date +%Y-%m-%d)"
run_omero "search Project --from=$today --to=$today"
run_omero "search Dataset --from=$today --to=$today"
run_omero "search Image --from=$today --to=$today --date-type=import"

echo "=== populate complete ==="
