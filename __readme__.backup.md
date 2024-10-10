# ONTOP Module for IDR on OMERO Backend

This repository contains the ONTOP module for the Image Data Resource (IDR) that runs on the OMERO backend.

## Acknowledgments

This project was developed with support from the Biohackathon 2024.

<img src="https://2024.biohackathon.org/images/bh24-logo.png" alt="Biohackathon 2024" width="200">

## Howto Ontop
### Software
- Protege: https://protege.stanford.edu/software.php#desktop-protege
- Unpack on your system into a writable directory
- Download ontop command line client (ontop-cli-x.y.z.zip) and ontop plugin for Protege (it.unibz.inf.ontop.protege-x.y.z.jar) from https://github.com/ontop/ontop/releases/latest
- Unpack ontop-cli zip 
- Save ontop plugin into your Protege's plugin directory.
- Download postgresql jdbc driver for your system's java version: https://jdbc.postgresql.org/download/
- Save the jdbc driver into the jdbc/ subdirectory of the unpacked ontop-cli archive.

### Configure omero postgres db
If you run ontop on a different host than your omero instance, you have to allow remote tcp/ip access to the latter via port 5432. By default, this is disabled and only connections from localhost are permitted.
To this end, edit these two files (paths may vary according to host OS, on debian/ubuntu servers it will likely be */etc/postgresql/VERSION/main/*). 
- *postgres.conf*
either allow all connections
```
listen_addresses = '*'          # what IP address(es) to listen on;
```
or specify clients as comma separated values:
```
listen_addresses = '192.168.1.10,172.5.16.4,localhost'          # what IP address(es) to listen on;
```

- *pg_hba.conf*
Adding these two lines worked for me but may be too permissive in your situation (in particular if your omero is not behind a firewall):
```
host    all             all             0.0.0.0/0               md5
host    all             all             ::/0                    md5
```

- restart your postgres service, i.e.
```
sudo service postgresql restart
```

### Test the connection
- Launch Protege
- If not present, add ontop Tabs (Menu -> Window -> Tabs -> Ontop Mappings)
- Configure postgres jdbc driver:
  - Select Menu -> File -> Preferences -> JDBC Drivers
  - Click Add
  - Select "org.postgresql.Driver" from Class name dropdown menu
  - Select postgres jdbc driver jar file downloaded earlier from the ontop-cli jdbc directory
- Setup connection:
  - In the Ontop Mappings Tab, select "Connection parameters" subtab
    - Enter connection URL: "jdbc:postgresql://your.omero.url:5432/omero"
    - Enter a db username with at least read access to all tables in the omero db.
    - Enter db user's password
    - Select "org.postgresql.Driver" as JDBC driver class.
- Click test connection
  - On error: Check postgres config on omero host and connection details.
  - On success: Hurray!
  
### Crunch time: Your first mapping
#### Add entity and property to active ontology
Add one class (e.g. `:Dataset`) and one data property (e.g. `:name`) to the ontology. 

More general, tables are mapped to classes, table index columns are mapped to
class instances (triple subjects), table columns headers are mapped to
properties (table predicates), table column values are mapped to property values
(table subjects).

#### Define mapping
- Select "Mapping manager" tab
- Click "New"
- Enter 
```ttl
:dataset/{id} a :Dataset;
              :name {name} .
```
into the field "Target" and
```sql
select id, name from dataset;
```
into the "Source" field.

You may want to test your query by clicking the "Execute the sql query" which will populate the "SQL Query results" field.

### SPARQL query
Select the "Ontop SPARQL" tab. Click "Prefixes" and select the base prefix and further prefixes as needed.
In the query editor enter
```sparql
select * where {
    ?subj a :Dataset;
          :name ?name .
}
```
And click "Execute". Find your omero dataset ids and names in the SPARQL results field and observe the generated SQL query in the "SQL tranlation" tab.

### Save mapping, ontology, and properties
Select Menu -> Save (or Save as). Select "Turtle syntax" for the file format and
select a file name. This filename will serve as the basis for three files:
*<filename>.properties* (db connection settings), *<filename>.ttl* (ontology),
and *<filename>.obda* (mapping definition in ontop format).

### Launch ontop SPARQL endpoint
In a terminal, navigate to the directory where you just saved your mapping definition files to.
In that directory, run

```console
path/to/ontop-cli/ontop endpoint -m <filename>.obda -t <filename>.ttl -p <filename>.properties
```

**replace** *<filename>* with the actual filename from above.

Open your webbrowser at http://localhost:8080 where a beautiful SPARQL frontend awaits your queries. Sparqly happy queries!
