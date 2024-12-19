#!/bin/bash

PGPASSWORD='postgres' psql -U postgres -h localhost -p 15432 < queries/sql/ontop_user.sql
