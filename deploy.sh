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
cp -v omero-ontop-mappings/core.owl.ttl ${PREFIX}/.

# Replace site prefix and URL
cat omero-ontop-mappings/omero-ontop-mappings.obda | sed "s/ome_instance/${PREFIX}/g" | sed "s/https:\/\/example\.org\/site\//${ESCSITE}/g" > ${PREFIX}/${PREFIX}.obda

# Adjust ontop launch script
cat omero-ontop-mappings/omero-ontop.sh | sed "s/omero-ontop-mappings/${PREFIX}/g" > ${PREFIX}/${PREFIX}-ontop.sh

# If all went well, echo how to start the endpoint
echo "Successfully deployed omero virtual knowledge graph in ${PREFIX}/ ."
echo ""
echo "You should now edit the file ${PREFIX}/${PREFIX}.properties and set the correct OMERO DB username, password, and URL."
echo ""
echo "To launch the SPARQL endpoint and query frontend, you can then `cd` into ${PREFIX}/"
echo "and run the provided script ${PREFIX}-ontop.sh."
echo ""



