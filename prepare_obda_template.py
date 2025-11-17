#!/usr/bin/env python3
from pathlib import Path

# Paths
src = Path("omero-ontop-mappings/omero-ontop-mappings.obda")
dst = Path("templates/{{cookiecutter.deploy_name}}/omero-ontop-mappings.obda")
dst.parent.mkdir(parents=True, exist_ok=True)

text = src.read_text()

# 1) Prefix line: ome_instance: https://example.org/site/
#    becomes: {{ cookiecutter.prefix }}: {{ cookiecutter.site_uri }}
text = text.replace(
    "ome_instance:\thttps://example.org/site/",
    "{{ cookiecutter.prefix }}:\t{{ cookiecutter.site_uri }}"
)

# 2) All other occurrences of ome_instance
text = text.replace(
    "ome_instance:",
    "{{ cookiecutter.prefix }}:"
)

# 3) Public condition: child=0  -> child{{ cookiecutter.publiccond }}
text = text.replace(
    "where child=0",
    "where child{{ cookiecutter.publiccond }}"
)

dst.write_text(text)
