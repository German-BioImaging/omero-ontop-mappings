#!/bin/sh

set -e

# Create the public user in omero and configure omero to login as public by default
omero login -C -u root -w omero -s localhost -p 14064
omero group add --type read-only public
omero user add -P public public Public User public
omero config set omero.web.public.enabled True
omero config set omero.web.public.user 'public'
omero config set omero.web.public.password 'public'
omero config set omero.web.public.server_id 1
