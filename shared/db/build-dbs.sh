#!/bin/bash

set -e
set -u

function create_database() {
	local database=$1
	local schema=$2
	echo "Creating database '$database' for '$POSTGRES_USER' if it doesn't already exist."
	psql -h postgres -v ON_ERROR_STOP=0 --username "$POSTGRES_USER" <<-EOSQL
			CREATE DATABASE "$database";
	    GRANT ALL PRIVILEGES ON DATABASE "$database" TO $POSTGRES_USER;
EOSQL
	echo "Creating schema '$schema' in '$database' if it doesn't already exist."
	psql -h postgres --username "$POSTGRES_USER" -d "$database" <<-EOSQL
		-- Create schemas
		CREATE SCHEMA IF NOT EXISTS $schema;
EOSQL
    # Special table creation for specific database and schema combinations
    if [ "$database" = "postgres" ] && [ "$schema" = "backend_ts" ]; then
        echo "Creating special table in $database.$schema"
        psql -h postgres --username "$POSTGRES_USER" -d "$database" <<-EOSQL
            CREATE TABLE IF NOT EXISTS $schema.backend_ts_users(id bigint NOT NULL);
EOSQL
    elif [ "$database" = "postgres" ] && [ "$schema" = "another_service" ]; then
        echo "Creating special table in $database.$schema"
        psql -h postgres --username "$POSTGRES_USER" -d "$database" <<-EOSQL
            CREATE TABLE IF NOT EXISTS $schema.another_service_users(id bigint NOT NULL);
EOSQL
    elif [ "$database" = "postgres2" ] && [ "$schema" = "backend_ts_test" ]; then
        echo "Creating special table in $database.$schema"
        psql -h postgres --username "$POSTGRES_USER" -d "$database" <<-EOSQL
            CREATE TABLE IF NOT EXISTS $schema.backend_ts_test_users(id bigint NOT NULL);
EOSQL
    elif [ "$database" = "postgres2" ] && [ "$schema" = "another_service_test" ]; then
        echo "Creating special table in $database.$schema"
        psql -h postgres --username "$POSTGRES_USER" -d "$database" <<-EOSQL
            CREATE TABLE IF NOT EXISTS $schema.another_service_test_users(id bigint NOT NULL);
EOSQL
    fi
}

echo "Waiting for postgres service to settle before building databases..."
sleep 10;


# Check if DB_SCHEMA_MAP is defined and not empty
if [ -n "${DB_SCHEMA_MAP:-}" ]; then
    echo "Using DB_SCHEMA_MAP for database and schema mapping"
    for mapping in $(echo $DB_SCHEMA_MAP | tr ';' ' '); do
        # Ensure the mapping has the correct format with a colon separator
        if [[ $mapping == *:* ]]; then
            # Extract database name and its schemas
            db=$(echo $mapping | cut -d':' -f1)
            schemas=$(echo $mapping | cut -d':' -f2)
            
            echo "Processing database: $db with schemas: $schemas"
            
            # Create each schema in the database
            for schema in $(echo $schemas | tr ',' ' '); do
                create_database $db $schema
            done
        else
            echo "Warning: Invalid mapping format: $mapping - skipping"
        fi
    done
else
    # Fallback to the original behavior if DB_SCHEMA_MAP is not provided or empty
    echo "DB_SCHEMA_MAP not provided or empty, using DB_NAMES and SCHEMA_NAMES"
    
    # Check if both DB_NAMES and SCHEMA_NAMES are provided
    if [ -n "${DB_NAMES:-}" ] && [ -n "${SCHEMA_NAMES:-}" ]; then
        for db in $(echo $DB_NAMES | tr ',' ' '); do
            # Trim any leading/trailing whitespace from the database name
            db=$(echo $db | xargs)
            echo "Processing database: $db with schemas from SCHEMA_NAMES"
            
            for schema in $(echo $SCHEMA_NAMES | tr ',' ' '); do
                # Trim any leading/trailing whitespace from the schema name
                schema=$(echo $schema | xargs)
                create_database $db $schema
            done
        done
    else
        echo "Error: Either DB_NAMES or SCHEMA_NAMES environment variables are not set."
        echo "Please provide both DB_NAMES and SCHEMA_NAMES or use DB_SCHEMA_MAP."
        exit 1
    fi
fi
    
echo "Databases built."

