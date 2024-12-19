# ONTOP for OMERO

This repository contains the code to create a virtual knowledge graph for OMERO using ontop-vkg mappings.

## Development 
For development, the omero-test-infra docker-compose file can be used. Follow these step to set it up:

### Get omero-test-infra
In the root of this repository:

```console
git clone https://github.com/ome/omero-test-infra .omero
```

### Patch the port mapping configuration
We need to access omero's postgresql database. Inside the container, it runs on port 5432 but is not
mapped to the host. We patch the docker-compose file to have the database served on postgresql://localhost:15432.

```console
cp utils/portmapping.patch .omero
cd .omero
patch -p1 < portmapping.patch
cd ..
```

### Add ontop database user
This step must be redone every time after resetting the test infrastructure.
```console
utils/setup_ontop_dbuser.short
```

### Get omero-py
Install omero-py via pip or from conda-forge. The script /utils\/install_omero-py.sh/ downloads and installs miniconda to the user's home directory and install omero-py as well as pytest and rdflib into the base environment.

```console
source utils/install_omero-py.sh
```

### Launch omero-test-infra
```console
.omero/docker dev start_up
```

### Populate omero with test data.
We need something to play with, so let's create some projects and datasets, import a few images and annotate 
with key-value pairs (map annotations) and tags.

```console
utils/insert_data.sh
```

### Launch ontop endpoint
Assuming `ontop` is in your path:
```console
ontop endpoint --mapping ontop/omemap.obda \
               --ontology ontop/omemap.ttl \
               --properties ontop/omemap.properties \
               --xml-catalog ontop/catalog-v001.xml \
               --dev
```
The commandline arguments point to the mappings file, mapping ontology, database connection details (properties), ontology import catalog, respectively. The `--dev` flag starts ontop int development mode. Edits to the mappings or ontology will trigger a restart of the endpoint. By default, the ontop endpoint is served at [http://localhost:8080/sparql](http://localhost:8080/sparql) , the query editor is at [http://localhost:8080](http://localhost:8080) . Use the `--port` option to configure a different port.

### Run tests
Finally,
```console
pytest
```
will run the python test suite.

### Reset database
To restart from a blank omero-test-infra (without images, datasets, projects, or annotations), run
```console
.omero/docker srv
```

Don't forget to restart it according to [above](#populate-omero-with-test-data).

## Acknowledgments

This project was developed with support from the Biohackathon 2024.

<img src="https://2024.biohackathon.org/images/bh24-logo.png" alt="Biohackathon 2024" width="200">


