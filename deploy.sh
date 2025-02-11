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
cp -avr template.d $PREFIX

# Cd into new dir
cd $PREFIX

# Rename files
cp omemap.properties ${PREFIX}.properties

# Replace site prefix and URL
cat omemap.obda | sed "s/ome_instance/${PREFIX}/g" | sed "s/https:\/\/example\.org\/site\//${ESCSITE}/g" > ${PREFIX}.obda



