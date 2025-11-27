# OMERO Virtual Knowledge Graph

This repository contains the code to create a virtual knowledge graph for [OMERO](https://openmicroscopy.org/omero) using [ontop-vkg](https://ontop-vkg.org) mappings.

## Install the Ontop command line client
The utility script in *utils\/install_ontop.sh* can be used to install the ontop cli into *ontop-cli*. We will assume the binary *ontop* is located in that directory. The script also installs the postgresql jdbc driver into *ontop-cli\/jdbc\/*.

## Deployment

To deploy your own OMERO–VKG instance, use the interactive deployment script included in this repository
(it assumes cookiecutter is installed and in your $PATH. If not, check https://www.cookiecutter.io).

### 1. Generate a deployment directory

From the top-level directory, run:

```bash
./deployment_cookiecutter.sh
```
The script will guide you through a series of questions, including:
 - PostgreSQL username, password, and host.
 - The RDF prefix for the deployment (used as folder name and ontology prefix).
 - The site URI (base URI for your instance).
 - A SQL filter controlling which OMERO users' data are exposed. Only data owned by the user(s) matching the filter and by users in the same groups as the filtered user(s) are mapped and accessible in the virtual KG. (e.g. =2 for a particular public OMERO user, or >=0 for all users).
 - Whether to create a QLever SPARQL endpoint and its UI.

After completing the prompts, a new directory named after your chosen prefix
(e.g. ome_instance) will be created.

### 2. Contents of the deployment directory

A typical deployment directory includes:

- PREFIX.ttl – The mapping ontology
- PREFIX.obda – OBDA mappings with your site prefix and URI
- PREFIX.properties – Database connection settings for ONTOP
- catalog-v001.xml – Imported third-party ontologies
- portal.toml – Metadata portal configuration
- PREFIX-ontop-endpoint.sh – Script to start the ONTOP SPARQL endpoint
- PREFIX-ontop-materialize.sh – Script to materialize the RDF graph
- qlever/ (optional) – Helper scripts for QLever indexing, server and qlever UI

### 3. Start the ONTOP SPARQL endpoint

```bash
cd PREFIX
./PREFIX-ontop-endpoint.sh
```
This will launch the ontop sparql query interface at http://localhost:8080, the endpoint is at http://localhost:8080/sparql (the Ontop endpoint will use the properties file that was automatically setup by the interactive deployment script).

### 4. (Optional) Use QLever as a high-performance SPARQL endpoint
```bash
cd PREFIX/
 ./PREFIX-ontop-materialize.sh  # Materialize RDF graph (.ttl format) 
cd qlever
./reindex_ome_data.sh           # Build QLever index
./start_qlever.sh               # Start QLever SPARQL server
./launch_qlever-ui-mpiebkg.sh   # Start the QLever web UI (optional)
```

**Note:** Materialization and QLever reindexing should be performed periodically. Otherwise the data will gradually
become outdated.

For more details see  
➡️ [Qlever configuration](docs/qlever_docs.md)


#### Create read-only OMERO DB user
Consult *utils/setup_ontop_dbuser.sh* and *queries/sql/ontop_user.sql* to setup the read-only DB user.

### Test setup
Run
```console
ontop-cli/ontop validate -m PREFIX/PREFIX.obda -t PREFIX/PREFIX.ttl -p PREFIX/PREFIX.properties -x PREFIX/catalog-v001.xml
```
to validate your deployment.

### Launch OMERO-VKG
Change into the deployment directory
```console
cd PREFIX
```
and run the `omero-ontop.sh` script

```console
bash omero-ontop.sh
```

This will launch the OMERO Virtual Knowledge Graph SPARQL endpoint at http://localhost:8080. You may wish to configure a different
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
### Get omero-py
Install omero-py via pip or from conda-forge. The script /utils\/install_omero-py.sh/ downloads and installs miniconda to the user's home directory and install omero-py as well as pytest and rdflib into the base environment.

```console
source utils/install_omero-py.sh
```

### Launch omero-test-infra
```console
.omero/docker dev start_up
```
### Add ontop database user
This step must be redone every time after resetting the test infrastructure.
```console
utils/setup_ontop_dbuser.sh
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
utils/test_infra-ontop.sh
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

<img src="https://2024.biohackathon.org/images/bh24-logo.png" alt="Biohackathon 2024" width="200">

This project was developed with support from the Biohackathon 2024 

This work is further supported by the Deutsche
Forschungsgemeinschaft (DFG, German Research Foundation) – 501864659
(NFDI4BIOIMAGE).


