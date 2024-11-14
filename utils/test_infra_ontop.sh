#! /bin/sh

# Spin up ontop
ontop-cli/ontop endpoint \
                -t test_infra_ontop/omemap.ttl \
                -m test_infra_ontop/omemap.obda \
                -p test_infra_ontop/omemap.properties \
                -x test_infra_ontop/catalog-v001.xml \
                --dev

