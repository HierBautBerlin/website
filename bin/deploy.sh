#!/bin/bash
set -e

VERSION=$1

# Update to latest version of code
cd "$HOME"/hierbautberlin
sed -i 's/LATEST_RELEASE=.*/LATEST_RELEASE='$VERSION'/g' env_vars

# Extract latest release
tar -xvf hierbautberlin-"$VERSION".tar.gz --one-top-level

# Find the port in use, and the available port
if curl --output /dev/null --silent --fail localhost:4000; then
  port_in_use=4000
  open_port=4001
else
  port_in_use=4001
  open_port=4000
fi

# Update release env vars with new port and set non-conflicting node name
echo "export PORT=${open_port}" >> hierbautberlin-"$VERSION"/releases/1.0.0+"$VERSION"/env.sh
echo "export RELEASE_NODE=hierbautberlin-${open_port}" >> hierbautberlin-"$VERSION"/releases/1.0.0+"$VERSION"/env.sh

# Sadly this weird hack is needed because the release tasks exit the bash script hard :(
finish_after_migration() {
  echo "Starting the app on port ${open_port}"

  # Start new instance of app
  sudo systemctl start hierbautberlin@${open_port}

  # Pause script till app is fully up
  until curl --output /dev/null --silent --fail http://localhost:$open_port/ping; do
    printf 'Waiting for app to boot...\n'
    sleep 3
  done

  printf "Grace period"
  sleep 10

  printf "Stopping ${port_in_use}"
  # Stop previous version of app
  sudo systemctl stop hierbautberlin@${port_in_use}
}

trap "finish_after_migration" EXIT
echo "Migrating"
export $(grep -v '^#' "$HOME"/hierbautberlin/env_vars | xargs)
"$HOME"/hierbautberlin/hierbautberlin-"$LATEST_RELEASE"/bin/hierbautberlin eval "Hierbautberlin.Release.migrate"
trap -

finish_after_migration
