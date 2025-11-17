#!/usr/bin/env bash
set -Eeuo pipefail

# Temporary working directory for Cookiecutter
OUT="tmp"                     
SETTINGS="${SETTINGS:-omero-ontop-config}"
BASE_DIR="omero-ontop-mappings"

# 1) Ensure tmp exists  and remove any old content
if [[ -d "$OUT" ]]; then  
  rm -rf "$OUT"
fi
mkdir -p "$OUT"

echo "🔧 Ontop deployment configuration"

# --- Ask user for values 
echo "Please enter OMERO username, password, and URL to connect to the OMERO DB."
read -r -p "jdbc_user: " JDBC_USER
while [[ -z "$JDBC_USER" ]]; do
  echo "jdbc_user cannot be empty."
  read -r -p "jdbc_user: " JDBC_USER
done

read -r -s -p "jdbc_password: " JDBC_PASS
echo
while [[ -z "$JDBC_PASS" ]]; do
  echo "jdbc_password cannot be empty."
  read -r -s -p "jdbc_password: " JDBC_PASS
  echo
done

read -r -p "db_host [ome.evolbio.mpg.de]: " DB_HOST
DB_HOST=${DB_HOST:-ome.evolbio.mpg.de}

echo "Enter PREFIX: RDF prefix for site instance, e.g. \"iob\"."
read -r -p "prefix [ome_instance]: " PREFIX
PREFIX=${PREFIX:-ome_instance}
echo "Enter URI: URI of site instance including trailing slash or #, e.g. \"https://institute.of.bioimaging.com/\"."
read -r -p "site_uri [https://example.org/site/]: " SITE_URI
SITE_URI=${SITE_URI:-https://example.org/site/}
echo "Enter PUBLICCOND: SQL Condition on \"user_id\" column that must evaluate to TRUE to map object. E.g. \"=2\" or \">=0\"."
read -r -p "publiccond [>=0]: " PUBLICCOND
PUBLICCOND=${PUBLICCOND:->=0}

echo ""
echo "Using:"
echo "  jdbc_user : $JDBC_USER"
echo "  db_host   : $DB_HOST"
echo "  prefix    : $PREFIX"
echo "  site_uri  : $SITE_URI"
echo "  publiccond: $PUBLICCOND"
echo ""

# 2) Build cookiecutter args 
CC_ARGS=(
  "templates"
  -o "$OUT"
  --no-input
  deploy_name="$SETTINGS"
  jdbc_user="$JDBC_USER"
  jdbc_password="$JDBC_PASS"
  db_host="$DB_HOST"
  prefix="$PREFIX"
  site_uri="$SITE_URI"
  publiccond="$PUBLICCOND"
)

echo "⚙️  Running Cookiecutter ..."
cookiecutter "${CC_ARGS[@]}"

# 3) Find the generated project directory inside $OUT
GEN_DIR=""
for d in "$OUT"/*; do
  if [[ -d "$d" ]]; then
    GEN_DIR="$d"
    break
  fi
done

if [[ -z "$GEN_DIR" ]]; then
  echo "❌ ERROR: No generated directory found in '$OUT'" >&2
  exit 1
fi

SRC_PROP="$GEN_DIR/omero-ontop-mappings.properties"
SRC_OBDA="$GEN_DIR/omero-ontop-mappings.obda"
SRC_ENV="$GEN_DIR/deploy.env"

if [[ ! -f "$SRC_PROP" ]]; then
  echo "❌ ERROR: Generated properties file not found at $SRC_PROP" >&2
  exit 1
fi

if [[ ! -f "$SRC_OBDA" ]]; then
  echo "❌ ERROR: Generated OBDA file not found at $SRC_OBDA" >&2
  exit 1
fi

if [[ ! -f "$SRC_ENV" ]]; then
  echo "❌ ERROR: deploy.env not found at $SRC_ENV" >&2
  exit 1
fi

# 4) Load PREFIX, SITE_URI, PUBLICCOND from deploy.env

. "$SRC_ENV"

if [[ -z "$PREFIX" ]]; then
  echo "❌ ERROR: PREFIX is empty after sourcing deploy.env" >&2
  exit 1
fi

echo "📁 Creating deployment folder '$PREFIX'..."
mkdir -p "$PREFIX"

# 5) Copy / rename files into deployment folder

# Properties from Cookiecutter (already escaped & chmodded by hook)
install -m 600 "$SRC_PROP" "${PREFIX}/${PREFIX}.properties"

# TTL from base dir, renamed
if [[ -f "$BASE_DIR/omero-ontop-mappings.ttl" ]]; then
  cp -v "$BASE_DIR/omero-ontop-mappings.ttl" "${PREFIX}/${PREFIX}.ttl"
fi

# Catalog + portal
if [[ -f "$BASE_DIR/catalog-v001.xml" ]]; then
  cp -v "$BASE_DIR/catalog-v001.xml" "${PREFIX}/."
fi

if [[ -f "$BASE_DIR/portal.toml" ]]; then
  cp -v "$BASE_DIR/portal.toml" "${PREFIX}/."
fi

# OBDA from Cookiecutter, renamed
cp -v "$SRC_OBDA" "${PREFIX}/${PREFIX}.obda"

# Ontop launch script
if [[ -f "$BASE_DIR/omero-ontop.sh" ]]; then
  sed "s/omero-ontop-mappings/${PREFIX}/g" "$BASE_DIR/omero-ontop.sh" > "${PREFIX}/${PREFIX}-ontop.sh"
  chmod +x "${PREFIX}/${PREFIX}-ontop.sh"
fi

# 6) Print confirmation (no password)
DEST_PROP="${PREFIX}/${PREFIX}.properties"

jdbc_user_final=$(grep -E '^jdbc\.user=' "$DEST_PROP" | sed 's/^jdbc\.user=//')
jdbc_url=$(grep -E '^jdbc\.url=' "$DEST_PROP" | sed 's/^jdbc\.url=//; s/\\:/:/g')
db_host_final=$(echo "$jdbc_url" | sed 's#^jdbc:postgresql://##; s/:5432.*$//')


echo ""
echo "✅ Deployment folder created: $PREFIX/"

echo ""
echo "   jdbc.user : $jdbc_user_final"
echo "   db_host   : $db_host_final"
echo "   jdbc.url  : $jdbc_url"
echo "   prefix    : $PREFIX"
echo "   site_uri  : $SITE_URI"
echo "   publiccond: $PUBLICCOND"
echo ""
echo "To start the endpoint:"
echo "  cd $PREFIX"
echo "  ./${PREFIX}-ontop.sh"
echo ""



################################################################################
# 7) Create materialization folder + script
################################################################################

MAT_DIR="materialize"
MAT_SCRIPT="${MAT_DIR}/materialize_data.sh"

mkdir -p "$MAT_DIR"

cat > "$MAT_SCRIPT" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

# Materialize VKG

# Directory of this script (materialize/)
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
# Project root = parent of materialize/
BASE_DIR="\$(cd "\$SCRIPT_DIR/.." && pwd)"

# Path to ONTOP CLI binary (adjust if needed)
ONTOPBIN="\$BASE_DIR/ontop-cli/ontop"

# Deployment folder name injected by cookiecutter
DEPLOY_DIR="\$BASE_DIR/${PREFIX}"

MAPPING="\$DEPLOY_DIR/${PREFIX}.obda"
ONTOLOGY="\$DEPLOY_DIR/${PREFIX}.ttl"
PROPERTIES="\$DEPLOY_DIR/${PREFIX}.properties"

OUTPUT="\$SCRIPT_DIR/materialized_data.ttl"

date
"\$ONTOPBIN" materialize \\
  --mapping "\$MAPPING" \\
  --ontology "\$ONTOLOGY" \\
  --properties "\$PROPERTIES" \\
  --format turtle \\
  --output "\$OUTPUT"
date
EOF

chmod +x "$MAT_SCRIPT"

echo ""
echo "🧪 Materialization script created:"
echo "   $MAT_SCRIPT"
echo "   Run it using:"
echo "     $MAT_SCRIPT"
echo ""

