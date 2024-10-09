#!/bin/bash

ONTOPBIN=/opt/ontop-cli/ontop
MAPPING=omemap.obda
ONTOLOGY=omemap.ttl
PROPERTIES=mpi.properties

$ONTOPBIN endpoint -m $MAPPING -t $ONTOLOGY -p $PROPERTIES 2>&1 > /dev/null
