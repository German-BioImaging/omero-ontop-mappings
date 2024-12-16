#!/bin/bash
# Launch ontop endpoint in dev mode on the omero_test_infra server.

ONTOPBIN=../ontop-cli/ontop
MAPPING=omemap.obda
ONTOLOGY=omemap.ttl
PROPERTIES=omemap.properties

$ONTOPBIN endpoint -m $MAPPING -t $ONTOLOGY -p $PROPERTIES -dev
