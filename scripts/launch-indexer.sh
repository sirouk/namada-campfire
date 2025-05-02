#!/usr/bin/env bash

# Examples for Mainnet or Housefire:
    # use latest tag:
    # unset BRANCH; BUILD_ONLY=false WIPE_DB=false CHAINDATA_PATH=$BASE_DIR $HOME/namada-campfire/scripts/launch-indexer.sh && docker logs -f --tail 100 namada-indexer-transactions-1

    # use branch:
    # BUILD_ONLY=false BRANCH=grarco/update-masp-events-rebased+fix WIPE_DB=false CHAINDATA_PATH=$BASE_DIR $HOME/namada-campfire/scripts/launch-indexer.sh && docker logs -f --tail 100 namada-indexer-transactions-1

# Example Campfire:

    # use latest tag:
    # unset BRANCH; BUILD_ONLY=false WIPE_DB=false CHAINDATA_PATH=$HOME/chaindata/namada-1 $HOME/namada-campfire/scripts/launch-indexer.sh && docker logs -f --tail 100 namada-indexer-transactions-1

    # use branch:
    # BUILD_ONLY=false BRANCH=grarco/update-masp-events-rebased+fix WIPE_DB=false CHAINDATA_PATH=$HOME/chaindata/namada-1 $HOME/namada-campfire/scripts/launch-indexer.sh && docker logs -f --tail 100 namada-indexer-transactions-1


# Set default values for environment variables
export BUILD_ONLY=${BUILD_ONLY:-false}
export BRANCH=${BRANCH:-""}
export WIPE_DB=${WIPE_DB:-false}
export POSTGRES_PORT="5432"
export POSTGRES_PASSWORD="password"
export DATABASE_URL="postgres://postgres:password@postgres:$POSTGRES_PORT/namada-indexer"
export TENDERMINT_URL=${TENDERMINT_URL:-"http://172.17.0.1:26657"}

export CAMPFIRE_CHAIN_DATA="$HOME/chaindata/namada-1"
export CHAINDATA_PATH=${CHAINDATA_PATH:-$CAMPFIRE_CHAIN_DATA}
export FOUND_CHAIN_ID=$(awk -F'=' '/default_chain_id/ {gsub(/[ "]/, "", $2); print $2}' "$CHAINDATA_PATH/global-config.toml")
export CHAIN_ID=${CHAIN_ID:-$FOUND_CHAIN_ID}

export CACHE_URL="redis://dragonfly:6379"
export WEBSERVER_PORT="6000"
export PORT="$WEBSERVER_PORT"

# Grab the repo
rm -rf $HOME/namada-indexer
cd $HOME
git clone https://github.com/anoma/namada-indexer.git
cd $HOME/namada-indexer

# Update the repo
git fetch --all

# Get the latest tag
LATEST_TAG=$(git describe --tags $(git rev-list --tags --max-count=1))
echo "Latest tag is: $LATEST_TAG"

# Checkout branch, tag, or specific version based on parameters
if [ -n "$BRANCH" ]; then
  # Use the specified branch
  echo "Using specified branch: $BRANCH"
  git checkout $BRANCH
  git pull
else
  # Use latest tag if no branch or tag specified
  echo "No branch or tag specified, using latest tag: $LATEST_TAG"
  git checkout $LATEST_TAG
  git reset --hard $LATEST_TAG
  git pull
fi

echo "Proceeding with CHAIN_ID: $CHAIN_ID, TENDERMINT_URL: $TENDERMINT_URL"

# add these values to docker-compose
yq -i '.services.chain.environment.CHECKSUMS_FILE = "checksums.json"' $HOME/namada-indexer/docker-compose.yml

# output vars to .env in root of namada-indexer
env_file="$HOME/namada-indexer/.env"
{
    echo "DATABASE_URL=\"$DATABASE_URL\""
    echo "TENDERMINT_URL=\"$TENDERMINT_URL\""
    echo "CHAIN_ID=\"$CHAIN_ID\""
    echo "CACHE_URL=\"$CACHE_URL\""
    echo "WEBSERVER_PORT=\"$WEBSERVER_PORT\""
    echo "PORT=\"$WEBSERVER_PORT\""
    echo "POSTGRES_PASSWORD=\"$POSTGRES_PASSWORD\""
} > "$env_file"

# copy checksums.json
cp -f $CHAINDATA_PATH/$CHAIN_ID/wasm/checksums.json $HOME/namada-indexer/checksums.json
echo "Copied $CHAINDATA_PATH/$CHAIN_ID/wasm/checksums.json"

# Skip teardown and start if BUILD_ONLY is true
if [ "$BUILD_ONLY" = false ]; then
  # tear down
  cd $HOME/namada-indexer
  docker stop $(docker container ls --all | grep 'namada-indexer' | awk '{print $1}') 2>/dev/null || true
  docker container rm --force $(docker container ls --all | grep 'namada-indexer' | awk '{print $1}') 2>/dev/null || true

  if [ "$WIPE_DB" = true ]; then
      docker compose -f $HOME/namada-indexer/docker-compose.yml down --volumes    
  else
      docker compose -f $HOME/namada-indexer/docker-compose.yml down
  fi

  POSTGRES_CONTAINER_ID=$(docker ps --filter "name=postgres" --filter "publish=${POSTGRES_PORT}" --format "{{.ID}}")
  if [ -n "$POSTGRES_CONTAINER_ID" ]; then
      echo "Stopping and removing 'postgres' container running on port ${POSTGRES_PORT}..."
      docker stop "$POSTGRES_CONTAINER_ID"
      docker rm "$POSTGRES_CONTAINER_ID"
      # remove the postgres image
      docker image rm --force $(docker image ls --all | grep -E '^postgres.*$' | awk '{print $3}') 2>/dev/null || true
  else
      echo "No 'postgres' container found running on port ${POSTGRES_PORT} (GOOD)"
  fi
  
  echo "Removing namada-indexer images"
  docker image rm --force $(docker image ls --all | grep -E '^namada/.*-indexer.*$' | awk '{print $3}') 2>/dev/null || true
  docker image rm --force $(docker image ls --all | grep '<none>' | awk '{print $3}') 2>/dev/null || true

  # prune all volumes (db data)
  if [ "$WIPE_DB" = true ]; then
      docker volume prune -fa
  fi
fi

# Fix the postgres-data to postgres_data in the docker-compose.yml file
sed -i 's/postgres-data/postgres_data/g' $HOME/namada-indexer/docker-compose.yml

# v2.5.2 is an all-in-one compose file without an includes directive
# Check if the campfire directory exists for the compose file
#if [ -d "$HOME/namada-campfire/docker/compose" ]; then
#  # Copy the docker compose file for the persistent db
#  cp -f $HOME/namada-campfire/docker/compose/docker-compose-db.yml $HOME/namada-indexer/docker-compose-db.yml
#  echo "Copied docker-compose-db.yml from namada-campfire"
#fi

# Build only or build and start
if [ "$BUILD_ONLY" = true ]; then
  # Just build
  docker compose -f $HOME/namada-indexer/docker-compose.yml --env-file $env_file build
  echo "Build completed. Run the following command when ready to launch:"
  echo "docker compose -f $HOME/namada-indexer/docker-compose.yml --env-file $env_file up -d"
else
  # Build and start the containers
  docker compose -f $HOME/namada-indexer/docker-compose.yml --env-file $env_file up -d
fi
