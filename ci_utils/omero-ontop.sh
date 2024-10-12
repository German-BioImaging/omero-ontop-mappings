#! /bin/bash

set -e

source ~/miniconda3/bin/activate

# Script to run as a single CI step in gh actions
# Launch omero
NOCLEAN=true .omero/docker dev start_up

# Inject data
omero login - localhost:14064 -u root -w omero
ci_utils/insert_data.sh

# Spin up ontop
ontop-cli/ontop endpoint -t mpieb/omemap.ttl -m mpieb/omemap.obda -p mpieb/omero-test-infra.properties 

# Check sparql endpoint is reachable
curl http://localhost:8080/sparql
