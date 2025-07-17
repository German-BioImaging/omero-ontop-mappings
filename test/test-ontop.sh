#!/bin/bash
# Launch ontop endpoint.
# Additional arguments and flags can be passed, e.g. `--dev` for development mode.

ONTOPBIN=../ontop-cli/ontop
MAPPING=test.obda
ONTOLOGY=test.ttl
PROPERTIES=test.properties
CATALOG=catalog-v001.xml

$ONTOPBIN endpoint --mapping $MAPPING \
                   --ontology $ONTOLOGY \
                   --properties $PROPERTIES \
                   --xml-catalog $CATALOG \
                   --cors-allowed-origins=* \
                   --portal portal.toml
                   $@
