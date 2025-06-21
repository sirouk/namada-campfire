#!/usr/bin/env bash

# Examples for Mainnet or Housefire:

  # use latest tag:
  # unset BRANCH; BUILD_ONLY=false WIPE_DB=false CHAINDATA_PATH=$BASE_DIR $HOME/namada-campfire/scripts/launch-masp-indexer.sh && docker logs -f --tail 100 namada-masp-indexer-crawler-1

  # use branch:
  # BUILD_ONLY=false BRANCH=v1.3.0 WIPE_DB=true CHAINDATA_PATH=$BASE_DIR $HOME/namada-campfire/scripts/launch-masp-indexer.sh && docker logs -f --tail 100 namada-masp-indexer-crawler-1

# Example Campfire:

  # use latest tag:
  # unset BRANCH; WIPE_DB=false CHAINDATA_PATH=$HOME/chaindata/namada-1 $HOME/namada-campfire/scripts/launch-masp-indexer.sh && docker logs -f --tail 100 namada-masp-indexer-crawler-1

  # use branch:
  # BUILD_ONLY=false BRANCH=tiago/housefire-indexer-1.3.x WIPE_DB=false CHAINDATA_PATH=$HOME/chaindata/namada-1 $HOME/namada-campfire/scripts/launch-masp-indexer.sh && docker logs -f --tail 100 namada-masp-indexer-crawler-1 


# Set BUILD_ONLY flag (defaults to true)
export BUILD_ONLY=${BUILD_ONLY:-true}
# Set BRANCH variable (if not set, will use the latest tag)
export BRANCH=${BRANCH:-""}

# Original behavior
rm -rf $HOME/namada-masp-indexer
cd $HOME
git clone https://github.com/anoma/namada-masp-indexer.git
cd $HOME/namada-masp-indexer

# Update the repo
git fetch --all

# Get the latest tag
LATEST_TAG=$(git describe --tags $(git rev-list --tags --max-count=1))
echo "Latest tag is: $LATEST_TAG"

# Checkout branch or tag based on BRANCH variable
if [ -z "$BRANCH" ]; then
  # Use latest tag if no branch specified
  echo "No branch specified, using latest tag: $LATEST_TAG"
  git checkout $LATEST_TAG
  git reset --hard $LATEST_TAG
  git pull
else
  # Use the specified branch
  echo "Using specified branch: $BRANCH"
  git checkout $BRANCH
  git pull
fi

# prep vars
export WIPE_DB=${WIPE_DB:-false}
export POSTGRES_PORT="5435" # or 5432
export TENDERMINT_URL=${TENDERMINT_URL:-"http://172.17.0.1:26657"}

# output vars to .env in root of namada-masp-indexer
env_file="$HOME/namada-masp-indexer/.env"
{
    echo "COMETBFT_URL=\"$TENDERMINT_URL\""
} > "$env_file"

# Load vars
source $env_file

# Skip teardown and start if BUILD_ONLY is true
if [ "$BUILD_ONLY" = false ]; then
  cd $HOME/namada-masp-indexer
  docker stop $(docker container ls --all | grep 'namada-masp-' | awk '{print $1}')
  docker container rm --force $(docker container ls --all | grep 'namada-masp-' | awk '{print $1}')

  # tear down
  if [ "$WIPE_DB" = true ]; then
      docker compose -f docker-compose.yml down --volumes
  else
      docker compose -f docker-compose.yml down
  fi

  POSTGRES_CONTAINER_ID=$(docker ps --filter "name=postgres" --filter "publish=${POSTGRES_PORT}" --format "{{.ID}}")
  if [ -n "$POSTGRES_CONTAINER_ID" ]; then
      echo "Stopping and removing 'postgres' container running on port ${POSTGRES_PORT}..."
      docker stop "$POSTGRES_CONTAINER_ID"
      docker rm "$POSTGRES_CONTAINER_ID"
      # remove the postgres image
      docker image rm --force $(docker image ls --all | grep -E '^postgres.*$' | awk '{print $3}')
  else
      echo "No 'postgres' container found running on port ${POSTGRES_PORT} (GOOD)"
  fi

  echo "Removing namada-masp-indexer images"
  docker image rm --force $(docker image ls --all | grep 'namada-masp-' | awk '{print $3}')
  docker image rm --force $(docker image ls --all | grep '<none>' | awk '{print $3}')

  # prune all volumes (db data)
  if [ "$WIPE_DB" = true ]; then
      docker volume prune -fa
  fi
fi

# Copy the docker compose file for the persistent db
#cp -f $HOME/namada-campfire/docker/compose/docker-compose-namada-masp-indexer.yml $HOME/namada-masp-indexer/docker-compose.yml

# Add the persistent db volume service to the docker compose file
yq -i 'select(.services.postgres | has("volumes") | not) |= .services.postgres.volumes = [{"type": "volume", "source": "namada-masp-indexer-postgres_data", "target": "/var/lib/postgresql/data"}]' $HOME/namada-masp-indexer/docker-compose.yml

# Add root volumes section if not present
yq -i 'select(has("volumes") | not) |= .volumes.namada-masp-indexer-postgres_data = {}' $HOME/namada-masp-indexer/docker-compose.yml


# Build only or build and start
if [ "$BUILD_ONLY" = true ]; then
  # Just build
  docker compose -f $HOME/namada-masp-indexer/docker-compose.yml --env-file $env_file build
  echo "Build completed. Run the following command when ready to launch:"
  echo "docker compose -f $HOME/namada-masp-indexer/docker-compose.yml --env-file $env_file up -d"
else
  # Build and start the containers (original behavior)
  docker compose -f $HOME/namada-masp-indexer/docker-compose.yml --env-file $env_file up -d
fi


# If WIPE_DB is true, then we need to restore the database from the snapshot
if [ "$WIPE_DB" = true ]; then
  # restore the database from the snapshot

  # Get the snapshot URL from the user
  echo "Visit https://docs.emberstake.xyz/networks/namada/snapshots#namada-masp-indexer-database-snapshot for the snapshot URL"
  read -p "Enter the snapshot URL: " SNAPSHOT_URL

  # Download the snapshot
  wget -O dump.sql $SNAPSHOT_URL

  # Stop the containers
  docker compose down

  # Start the postgres container
  docker compose up -d postgres

  # Copy the snapshot to the postgres container
  docker compose cp dump.sql postgres:/tmp/dump.sql

  # Wait for postgres to be fully ready (check health status)
  echo "Waiting for postgres container to be healthy..."
  while ! docker compose ps postgres | grep -q "healthy"; do
    echo "Waiting for postgres container to be healthy..."
    sleep 2
  done
  
  # Give it a few more seconds to ensure PostgreSQL is fully ready
  sleep 5

  # Restore the database
  docker compose exec postgres pg_restore -U postgres -d masp_indexer_local --clean --if-exists /tmp/dump.sql --verbose

  # Remove the snapshot from the container
  docker compose exec postgres rm /tmp/dump.sql
  
  # Remove the local snapshot file
  rm -f dump.sql

  # Start the containers
  docker compose up -d
fi
