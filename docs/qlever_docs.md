# QLever Configuration and Usage Guide  

If  a QLever instance was enabled during deployment, you will find a directory:

```bash
cd PREFIX/qlever
```

## Before you begin
Ensure you have:

- ✔ **Docker** installed and running  
- ✔ Confirmed that your `PREFIX.properties` file (generated automatically during  
  deployment) contains the correct PostgreSQL username, password. The template uses port **5432**. This might different for other servers.
- ✔ Completed RDF materialization using  
  `PREFIX/PREFIX-ontop-materialize.sh`  

Your materialized RDF file is usually:
```bash
cd PREFIX/materialized_data.ttl
```