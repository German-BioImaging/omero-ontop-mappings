#! /bin/sh

# Spin up ontop
ontop-cli/ontop endpoint \
                -t ontop/omemap.ttl \
                -m ontop/omemap.obda \
                -p ontop/omemap.properties \
                -x ontop/catalog-v001.xml \
                --dev

