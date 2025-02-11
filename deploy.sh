#! /bin/sh

set -e

# Read arguments
if [ ! $# -eq 2 ]
then
   echo "Usage: deploy.sh PREFIX URI"
fi

PREFIX=$1
SITE=$2

# Function to escape special characters in a string
ESCSITE=$(echo $SITE | sed -e 's/[]\/$*.^[]/\\&/g')

echo $(escape_regex "$SITE")

echo "Deploying site $SITE with prefix $PREFIX."
# Copy ontop dir
mkdir -vp $PREFIX

# Rename files
cp -v omero-ontop-mappings/omero-ontop-mappings.properties ${PREFIX}/${PREFIX}.properties
cp -v omero-ontop-mappings/omero-ontop-mappings.ttl ${PREFIX}/${PREFIX}.ttl
cp -v omero-ontop-mappings/catalog-v001.xml ${PREFIX}/.

# Replace site prefix and URL
cat omero-ontop-mappings/omero-ontop-mappings.obda | sed "s/ome_instance/${PREFIX}/g" | sed "s/https:\/\/example\.org\/site\//${ESCSITE}/g" > ${PREFIX}/${PREFIX}.obda



