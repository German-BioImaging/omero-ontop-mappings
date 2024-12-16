#!/bin/bash
# Launch ontop endpoint in dev mode on the omero_test_infra server.

ONTOPBIN=../ontop-cli/ontop
MAPPING=omemap.obda
ONTOLOGY=omemap.ttl
PROPERTIES=omemap.properties
CATALOG=catalog-v001.xml

$ONTOPBIN endpoint -m $MAPPING -t $ONTOLOGY -p $PROPERTIES -x $CATALOG -dev
