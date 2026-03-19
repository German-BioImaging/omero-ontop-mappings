#!/usr/bin/env bash
set -euo pipefail
# Script to populate OMERO with test data as in insert_data.sh, but adapted for CI usage 
#inside the container to avoid SSL issues with OMERO.java CLI on host.
# NOTE: do not run it on the terminal, use insert_data.sh instead when working locally.

COMPOSE_FILE=".omero/docker-compose.yml"
SERVICE="omero"
# OMERO CLI path 
OMERO_BIN="/opt/omero/server/OMERO.server/bin/omero"

# Inside container, OMERO listens on 4064 for SSL 
HOST_IN_CONTAINER="localhost"
PORT_SSL_IN_CONTAINER="4064"

USER="${OMERO_USER:-root}"
PASS="${OMERO_PASS:-omero}"

REPO_IN_CONTAINER="/repo"
IMG_DIR="${REPO_IN_CONTAINER}/img"

die() { echo "ERROR: $*" >&2; exit 1; }

echo "compose:  $COMPOSE_FILE"
echo "service:  $SERVICE"
echo "omero:    $OMERO_BIN"
echo "server:   $HOST_IN_CONTAINER:$PORT_SSL_IN_CONTAINER (SSL)"
echo "repo:     $REPO_IN_CONTAINER"
echo "img dir:  $IMG_DIR"
echo "user:     $USER"

# Verify OMERO CLI exists in container
docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" sh -lc "test -x '$OMERO_BIN' && '$OMERO_BIN' version" \
  || die "OMERO CLI not found/executable at $OMERO_BIN"

# Verify repo mount exists
docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" sh -lc "test -d '$IMG_DIR' && ls -la '$IMG_DIR' >/dev/null" \
  || die "Repo not mounted at $REPO_IN_CONTAINER. Ensure override has: volumes: - ..:/repo:ro"

# Wait for OMERO readiness 
echo "Waiting for OMERO.server to accept sessions..."
for i in $(seq 1 180); do
  if docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" sh -lc \
      "$OMERO_BIN -u '$USER' -w '$PASS' -s '$HOST_IN_CONTAINER' -p '$PORT_SSL_IN_CONTAINER' -C hql \"select count(e.id) from Experimenter e\" >/dev/null 2>&1"; then
    echo "OMERO is ready."
    break
  fi
  echo "  not ready yet ($i/180) ..."
  docker compose -f "$COMPOSE_FILE" logs --no-color --tail=25 omero || true
  sleep 2
done

# Hard fail if still not ready
docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" sh -lc \
  "$OMERO_BIN -u '$USER' -w '$PASS' -s '$HOST_IN_CONTAINER' -p '$PORT_SSL_IN_CONTAINER' -C hql \"select count(e.id) from Experimenter e\" >/dev/null" \
  || die "OMERO never became ready"

# Helper to run OMERO commands inside container
omero_in() {
  docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" sh -lc \
    "$OMERO_BIN -u '$USER' -w '$PASS' -s '$HOST_IN_CONTAINER' -p '$PORT_SSL_IN_CONTAINER' -C $*"
}

# ---- Create 3 datasets ----
DS1="$(omero_in "obj new Dataset name='Dataset 1'")"
DS2="$(omero_in "obj new Dataset name='Dataset 2'")"
DS3="$(omero_in "obj new Dataset name='Dataset 3'")"
echo "Datasets: $DS1 $DS2 $DS3"

# ---- Annotations (dataset-level) ----
MAP1="$(omero_in "obj new MapAnnotation ns='http://purl.org/dc/terms/'")"
omero_in "obj new DatasetAnnotationLink parent='$DS1' child='$MAP1'"
omero_in "obj map-set '$MAP1' mapValue contributor 'Test User'"
omero_in "obj map-set '$MAP1' mapValue subject 'Test images'"
omero_in "obj map-set '$MAP1' mapValue provenance 'Screenshots'"

TAG1="$(omero_in "tag create --name 'TestTag'")"
omero_in "obj new DatasetAnnotationLink parent='$DS1' child='$TAG1'"

MAP2="$(omero_in "obj new MapAnnotation ns='http://purl.org/dc/terms/'")"
# Preserve your original behavior (DS2 linked to MAP1)
omero_in "obj new DatasetAnnotationLink parent='$DS2' child='$MAP1'"
omero_in "obj map-set '$MAP2' mapValue contributor 'Anonymous'"
omero_in "obj map-set '$MAP2' mapValue subject 'Ontop Tutorial'"
omero_in "obj map-set '$MAP2' mapValue provenance 'Screenshots'"

MAP3="$(omero_in "obj new MapAnnotation ns='http://purl.org/dc/terms/'")"
omero_in "obj new DatasetAnnotationLink parent='$DS3' child='$MAP3'"
omero_in "obj map-set '$MAP3' mapValue contributor 'Caligula'"
omero_in "obj map-set '$MAP3' mapValue subject 'OMERO Mapping'"
omero_in "obj map-set '$MAP3' mapValue provenance 'Screenshots'"

# ---- Create Project + link datasets ----
PROJ="$(omero_in "obj new Project name='Project'")"
omero_in "obj new ProjectDatasetLink parent='$PROJ' child='$DS1'"
omero_in "obj new ProjectDatasetLink parent='$PROJ' child='$DS2'"
omero_in "obj new ProjectDatasetLink parent='$PROJ' child='$DS3'"

# ---- Project annotation ----
MAP4="$(omero_in "obj new MapAnnotation ns='http://purl.org/dc/terms/'")"
omero_in "obj new ProjectAnnotationLink parent='$PROJ' child='$MAP4'"
omero_in "obj map-set '$MAP4' mapValue contributor 'Nophretete'"
omero_in "obj map-set '$MAP4' mapValue subject 'OMERO Ontology'"
omero_in "obj map-set '$MAP4' mapValue provenance 'Test Data'"

# ---- Import images from /repo/img (FIXED: avoid $1/$2 expansion with set -u) ----
echo "=== Importing images from /repo/img ==="
docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" sh -lc "
  echo \"  14-png: \$(find '$IMG_DIR' -type f -name '*_14-*.png' | wc -l)\"
  echo \"  15-png: \$(find '$IMG_DIR' -type f -name '*_15-*.png' | wc -l)\"
  echo \"  16-png: \$(find '$IMG_DIR' -type f -name '*_16-*.png' | wc -l)\"
  echo \"  ome.tif: \$(find '$IMG_DIR' -type f -name '*.ome.tif' | wc -l)\"
"

echo "Importing PNG screenshots..."
docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" sh -lc "
  set -e

  echo \"Importing *_14-*.png -> $DS1\"
  find '$IMG_DIR' -type f -name '*_14-*.png' -print0 | sort -z | while IFS= read -r -d '' f; do
    echo \"  Import \$f -> $DS1\"
    '$OMERO_BIN' -u '$USER' -w '$PASS' -s '$HOST_IN_CONTAINER' -p '$PORT_SSL_IN_CONTAINER' -C import \"\$f\" -d '$DS1'
  done

  echo \"Importing *_15-*.png -> $DS2\"
  find '$IMG_DIR' -type f -name '*_15-*.png' -print0 | sort -z | while IFS= read -r -d '' f; do
    echo \"  Import \$f -> $DS2\"
    '$OMERO_BIN' -u '$USER' -w '$PASS' -s '$HOST_IN_CONTAINER' -p '$PORT_SSL_IN_CONTAINER' -C import \"\$f\" -d '$DS2'
  done

  echo \"Importing *_16-*.png -> $DS3\"
  find '$IMG_DIR' -type f -name '*_16-*.png' -print0 | sort -z | while IFS= read -r -d '' f; do
    echo \"  Import \$f -> $DS3\"
    '$OMERO_BIN' -u '$USER' -w '$PASS' -s '$HOST_IN_CONTAINER' -p '$PORT_SSL_IN_CONTAINER' -C import \"\$f\" -d '$DS3'
  done
"

echo "Importing OME-TIFFs with ROI into DS2..."
docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" sh -lc "
  set -e
  find '$IMG_DIR' -type f -name '*.ome.tif' -print0 | sort -z | while IFS= read -r -d '' f; do
    echo \"  Import \$f -> $DS2\"
    '$OMERO_BIN' -u '$USER' -w '$PASS' -s '$HOST_IN_CONTAINER' -p '$PORT_SSL_IN_CONTAINER' -C import \"\$f\" -d '$DS2'
  done
"

# ---- Image annotations to match original script ----

# Tag used for first 10 images
TAG2="$(omero_in "tag create --name 'Screenshot'")"

# For images 1..10:
# - create MapAnnotation (with dcterms namespace)
# - link it to Image:<idx>
# - set date/contributor/subject
# - link Screenshot tag to Image:<idx>
for image_index in $(seq 1 10); do
  ann="$(omero_in "obj new MapAnnotation ns='http://purl.org/dc/terms/'")"
  omero_in "obj new ImageAnnotationLink parent='Image:$image_index' child='$ann'"
  omero_in "obj map-set '$ann' mapValue date \"\$(date)\""
  omero_in "obj map-set '$ann' mapValue contributor 'Test User'"
  omero_in "obj map-set '$ann' mapValue subject 'Unittest'"
  omero_in "obj new ImageAnnotationLink parent='Image:$image_index' child='$TAG2'"
done

# Image:12 MapAnnotation without namespace
ann_no_ns="$(omero_in "obj new MapAnnotation")"
omero_in "obj new ImageAnnotationLink parent='Image:12' child='$ann_no_ns'"
omero_in "obj map-set '$ann_no_ns' mapValue annotator 'MrX'"

# Image:11 MapAnnotation with namespace that is not a valid URI
ann_non_uri="$(omero_in "obj new MapAnnotation ns='www.openmicroscopy.org/ns/default'")"
omero_in "obj new ImageAnnotationLink parent='Image:11' child='$ann_non_uri'"
omero_in "obj map-set '$ann_non_uri' mapValue sampletype 'screen'"

# Image:10 MapAnnotation with namespace that is not a valid URI (issue #16)
ann_issue16="$(omero_in "obj new MapAnnotation ns='hms.harvard.edu/omero/forms/kvdata/MPB Annotations/'")"
omero_in "obj new ImageAnnotationLink parent='Image:10' child='$ann_issue16'"
omero_in "obj map-set '$ann_issue16' mapValue Assay 'PRTSC'"

# Image:9 MapAnnotation with namespace that starts with "/" (issue #17)
ann_issue17="$(omero_in "obj new MapAnnotation ns='/MouseCT/Skyscan/System'")"
omero_in "obj new ImageAnnotationLink parent='Image:9' child='$ann_issue17'"
omero_in "obj map-set '$ann_issue17' mapValue Assay 'Bruker'"

# Image:1 Map annotations with special characters (no namespace)
ann_special="$(omero_in "obj new MapAnnotation")"
omero_in "obj new ImageAnnotationLink parent='Image:1' child='$ann_special'"
omero_in "obj map-set '$ann_special' mapValue 'foo^bar' 'bar'"
omero_in "obj map-set '$ann_special' mapValue '\$foo*bar#ba' 'some**thing'"
omero_in "obj map-set '$ann_special' mapValue '&*foo&^bar' 'cool'"

# ---- List all objects  ----
today="$(date +%Y-%m-%d)"
omero_in "search Project --from=$today --to=$today"
omero_in "search Dataset --from=$today --to=$today"
omero_in "search Image --from=$today --to=$today --date-type=import"

echo "=== populate complete ==="

