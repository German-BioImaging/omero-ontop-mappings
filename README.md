# OMERO Virtual Knowledge Graph

This repository contains the code to create a virtual knowledge graph for [OMERO](https://openmicroscopy.org/omero) using [ontop-vkg](https://ontop-vkg.org) mappings.

## Deployment
To deploy your own OMERO-VKG, follow these steps:
### Generate site configuration directory
In the top level directory, run the command
```console
bash deploy.sh PREFIX URI
```
Replace `PREFIX` AND `URI` with the prefix name and URL for your OMERO instance, respectively. E.g. for the (hypothetical ) Institute of Bioimaging, which
runs OMERO at the URL `https://ome.iob.net`, a sensible choice would be `setup_site.sh iob https://ome.iob.net/`.

This will create a new directory named after the `PREFIX` (/iob\//) in the example above, containing four files:

1. /iob\/omemap.ttl/: The mapping ontology
1. /iob\/iob.obda/: The mappings with adjusted site prefix and URL.
1. /iob\/catalog-v001.xml/: 3rd party ontologies imported into /omemap.ttl/, in particular the OME core ontology.
1. /job\/iob.properties/: Properties file containing the database connection parameters.

### Edit properties file
In the properties file, you need to change the values for `jdbc.user`, `jdbc.password`, and `jdbc.url`. Consider setting up a read-only database user (role)
with SELECT rights on the public database tables. The `jdbc.url` should be configured according to your OMERO DB host's hostname and port on which
the postgresql daemon accepts requests. Leave the `jdbc.driver` value as it is.

### Test setup
Run
```console
ontop-cli/ontop validate -m PREFIX/PREFIX.obda -t PREFIX/omemap.ttl -p PREFIX/PREFIX.properties -x PREFIX/catalog-v001.xml
```
to validate your deployment.

### Launch OMERO-VKG
Run
```console
ontop-cli/ontop endpoint -m PREFIX/PREFIX.obda -t PREFIX/omemap.ttl -p PREFIX/PREFIX.properties -x PREFIX/catalog-v001.xml
```

If all goes well, this will launch the OMERO Virtual Knowledge Graph SPARQL endpoint at http://localhost:8080. You may wish to configure a different
port and/or hostname. Consult the ontop-cli user manual to this effect (`ontop-cli/ontop help endpoint`). 

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
utils/setup_ontop_dbuser.sh
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
omero-ontop-mappings endpoint --mapping omero-ontop-mappings/omero-ontop-mappings.obda \
               --ontology omero-ontop-mappings/omero-ontop-mappings.ttl \
               --properties omero-ontop-mappings/omero-ontop-mappings.properties \
               --xml-catalog omero-ontop-mappings/catalog-v001.xml \
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


