#! /bin/bash

# Spin up ontop
ontop endpoint \
                -t omemap.ttl \
                -m omemap.obda \
                -p omemap.properties \
                -x catalog-v001.xml \
                --dev

