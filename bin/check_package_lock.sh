#!/bin/sh
# Checks that assets/package-lock.json matches deps/. phoenix, phoenix_html and
# phoenix_live_view are file: dependencies, so their version in the lock file
# comes from deps/. Dependabot only bumps mix.lock and the docker build then
# fails with its older npm.
#
# Rewrites the lock file when it is out of date, so the change only has to be
# committed.
set -e

cd "$(dirname "$0")/../assets"

before=$(mktemp)
trap 'rm -f "$before"' EXIT
cp package-lock.json "$before"

npm install --package-lock-only --no-audit --no-fund >/dev/null

if ! diff -u "$before" package-lock.json; then
  echo "assets/package-lock.json was out of date and has been updated, commit the change"
  exit 1
fi
