#!/bin/bash
# Launch ontop endpoint.
# Additional arguments and flags can be passed, e.g. `--dev` for development mode.

ONTOPBIN=../ontop-cli/ontop
MAPPING=omeswat.obda
ONTOLOGY=omeswat.ttl
PROPERTIES=omeswat.properties
CATALOG=catalog-v001.xml

cmd="$ONTOPBIN endpoint \
--mapping $MAPPING \
--ontology $ONTOLOGY \
--properties $PROPERTIES \
--xml-catalog $CATALOG \
--cors-allowed-origins=* \
--portal portal.toml $@"

echo $cmd
eval $cmd
