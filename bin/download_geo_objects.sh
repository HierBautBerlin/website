#!/bin/sh
set -e

echo

if ! command -v curl >/dev/null 2>&1
then
  echo >&2 "Please install curl before running this script"; 
  exit 1; 
fi

if ! command -v osmconvert >/dev/null 2>&1
then
  echo >&2 "Please install osmconvert before running this script"; 
  echo >&2 "https://wiki.openstreetmap.org/wiki/Osmconvert"; 
  exit 1; 
fi

mkdir -p data

echo "#############################"
echo "# 🛣   Downloading streets "
echo "#############################"
echo

curl http://download.geofabrik.de/europe/germany/berlin-latest.osm.pbf > data/berlin-latest.osm.pbf

echo
echo "#############################"
echo "# 📇   Generating street CSV "
echo "#############################"

osmconvert data/berlin-latest.osm.pbf -o=data/berlin-latest.o5m
osmfilter data/berlin-latest.o5m --keep="addr:street="  --ignore-depencencies --drop-relations --drop-ways  | osmconvert -  --csv-separator=";" --csv="@id addr:street addr:housenumber addr:postcode addr:city addr:suburb @lon @lat" -o=data/street_with_number.csv

echo
echo "#############################"
echo "# 📨  Importing into DB "
echo "#############################"

mix import_streets