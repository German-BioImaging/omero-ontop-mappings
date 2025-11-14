#! /bin/bash
set -e

omero login -C -u root -w omero -s localhost:14064

# Create a Screen
Screen=$(omero obj new Screen name="IDR0017-Screen")

# Import HCS dataset
omero import img/idr0017/idr0017.xdce -T $Screen
