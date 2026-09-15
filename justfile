# List all recipes
default:
    @just --list

# Start the dev server on http://localhost:4000
start:
    mix phx.server

# Start the PostGIS container (podman, port 5434, see README)
db:
    podman start hierbautberlin-db

# Create and migrate the database, install and build assets
setup:
    mix setup

# Fetch dependencies and install the asset tools
update:
    mix deps.get
    mix assets.setup

# Run the tests in watch mode
run-tests:
    mix test.watch --stale

# Formatter, credo, dialyzer and tests
check:
    mix check

# Extract and merge gettext translations
i18n:
    mix gettext.extract
    mix gettext.merge priv/gettext

# Restore a production dump into a new database (fails if it already exists)
restore-dump file="dump.sql" name="hierbautberlin_prod":
    #!/bin/sh
    set -e
    export PGPASSWORD="${PGPASSWORD:-postgres}"
    psql="psql -h ${DATABASE_HOST:-localhost} -p ${DATABASE_PORT:-5432} -U postgres"
    $psql -c 'CREATE DATABASE "{{ name }}"'
    # the dump sets the production role as owner, those errors are expected
    $psql -q -o /dev/null -d "{{ name }}" -f "{{ file }}" 2>&1 | grep -v 'role "hierbautberlin" does not exist' || true
    echo "Restored {{ file }} into {{ name }}, use it with DATABASE_NAME={{ name }}"

# Import streets, street numbers and places (downloads the OSM extract of Berlin)
import-geo:
    bin/import_geo_objects.sh

# Run the address matching again for a source, e.g. `just reanalyze BERLIN_PRESSE --apply`
reanalyze source *args:
    mix geo.reanalyze {{ source }} {{ args }}

# Evaluate the address matching against the gold set
eval-matching *args:
    mix run bench/matching/eval.exs {{ args }}
