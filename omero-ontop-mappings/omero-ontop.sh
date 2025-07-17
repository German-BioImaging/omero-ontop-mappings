#!/bin/bash
# Launch ontop endpoint.
# Additional arguments and flags can be passed, e.g. `--dev` for development mode.

ONTOPBIN=../ontop-cli/ontop
MAPPING=omero-ontop-mappings.obda
ONTOLOGY=omero-ontop-mappings.ttl
PROPERTIES=omero-ontop-mappings.properties
CATALOG=catalog-v001.xml

$ONTOPBIN endpoint --mapping $MAPPING \
                   --ontology $ONTOLOGY \
                   --properties $PROPERTIES \
                   --xml-catalog $CATALOG \
                   --cors-allowed-origins=* \
                   --portal portal.toml
                   $@
