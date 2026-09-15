#!/bin/sh
# Downloads the current OpenStreetMap extract of Berlin and imports streets,
# street numbers and places (parks, LOR planning areas, schools) into the
# database. Running it again updates the data and keeps all links to news items.
#
# Needs curl and ogr2ogr (Debian: gdal-bin).
#
#   bin/import_geo_objects.sh            # local development (mix)
#   bin/import_geo_objects.sh --release  # on the server, using the release in $RELEASE_DIR
set -e

if ! command -v curl >/dev/null 2>&1; then
  echo >&2 "Please install curl before running this script"
  exit 1
fi

if ! command -v ogr2ogr >/dev/null 2>&1; then
  echo >&2 "Please install ogr2ogr before running this script (Debian: gdal-bin)"
  exit 1
fi

DATA_DIR=${DATA_DIR:-data}
OSM_FILE="$DATA_DIR/berlin-latest.osm.pbf"
mkdir -p "$DATA_DIR"

echo "Downloading OpenStreetMap extract (only if it changed)"
if [ -f "$OSM_FILE" ]; then
  curl -fL -z "$OSM_FILE" -o "$OSM_FILE" https://download.geofabrik.de/europe/germany/berlin-latest.osm.pbf
else
  curl -fL -o "$OSM_FILE" https://download.geofabrik.de/europe/germany/berlin-latest.osm.pbf
fi

if [ "$1" = "--release" ]; then
  "$RELEASE_DIR"/bin/hierbautberlin eval "Hierbautberlin.Release.import_geo_data(\"$(realpath "$OSM_FILE")\")"
else
  mix import_osm "$OSM_FILE"
  mix import_places
fi
