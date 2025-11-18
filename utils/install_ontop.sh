#!/bin/sh

wget https://github.com/ontop/ontop/releases/download/ontop-5.4.0/ontop-cli-5.4.0.zip
mkdir -p ontop-cli
cd ontop-cli
unzip ../ontop-cli-5.4.0.zip
cd jdbc
wget https://jdbc.postgresql.org/download/postgresql-42.7.4.jar
