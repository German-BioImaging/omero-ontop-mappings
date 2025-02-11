#!/bin/bash
# Launch ontop endpoint in dev mode on the omero_test_infra server.

ONTOPBIN=ontop-cli/ontop
MAPPING=omero-ontop-mappings/omero-ontop-mappings.obda
ONTOLOGY=omero-ontop-mappings/omero-ontop-mappings.ttl
PROPERTIES=omero-ontop-mappings/omero-ontop-mappings.properties
CATALOG=omero-ontop-mappings/catalog-v001.xml

$ONTOPBIN endpoint -m $MAPPING -t $ONTOLOGY -p $PROPERTIES -x $CATALOG --dev
