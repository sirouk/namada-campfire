#!/usr/bin/env bash


# Grab the repo
rm -rf $HOME/namada-indexer
cd $HOME
git clone https://github.com/anoma/namada-indexer.git
#git clone https://github.com/sirouk/namada-indexer.git
cd $HOME/namada-indexer && git fetch --all
#git checkout master
#cd $HOME/namada-indexer && git fetch --all && git checkout chore/update-namada-to-0.43.0 && git pull
#cd $HOME/namada-indexer && git fetch --all && git checkout patch-2 && git pull
#git checkout tags/v1.0.1

# Get the latest tag
LATEST_TAG=$(git describe --tags $(git rev-list --tags --max-count=1))
git checkout $LATEST_TAG
git reset --hard $LATEST_TAG
git pull

#git checkout fix-transparent-tx-kind
#git pull

# Copy the docker compose file for the db
cp $HOME/namada-campfire/docker/compose/docker-compose-db.yml $HOME/namada-indexer/docker-compose-db.yml


# prep are vars
export WIPE_DB=${WIPE_DB:-false}
export POSTGRES_PORT="5433"
#export DATABASE_URL="postgres://postgres:password@0.0.0.0:$POSTGRES_PORT/namada-indexer"
export DATABASE_URL="postgres://postgres:password@postgres:$POSTGRES_PORT/namada-indexer"
#export DATABASE_URL_TEST="postgres://postgres:password@0.0.0.0:$POSTGRES_PORT"
export TENDERMINT_URL=${TENDERMINT_URL:-"http://172.17.0.1:26657"}
#export TENDERMINT_URL="http://127.0.0.1:27657"

export CAMPFIRE_CHAIN_DATA="$HOME/chaindata/namada-1"
export CHAINDATA_PATH=${CHAINDATA_PATH:-$CAMPFIRE_CHAIN_DATA}
export FOUND_CHAIN_ID=$(awk -F'=' '/default_chain_id/ {gsub(/[ "]/, "", $2); print $2}' "$CHAINDATA_PATH/global-config.toml")
export CHAIN_ID=${CHAIN_ID:-$FOUND_CHAIN_ID}


export CACHE_URL="redis://dragonfly:6379"
#export CACHE_URL="redis://redis@0.0.0.0:6379"
export WEBSERVER_PORT="6000"
export PORT="$WEBSERVER_PORT"

echo "Proceeding with CHAIN_ID: $CHAIN_ID, TENDERMINT_URL: $TENDERMINT_URL"


# update the values for this chain in the docker compose file
#yq -i ".services[].environment.DATABASE_URL = \"postgres://postgres:password@postgres:5432/namada-indexer\"" $HOME/namada-indexer/docker-compose.yml
#yq -i ".services[].environment.TENDERMINT_URL = \"$TENDERMINT_URL\"" $HOME/namada-indexer/docker-compose.yml
#yq -i ".services[].environment.CHAIN_ID = \"$CHAIN_ID\"" $HOME/namada-indexer/docker-compose.yml
#yq -i '.services.webserver.ports[] |= sub("5000:5000", "6000:5000")' $HOME/namada-indexer/docker-compose.yml

# add these values
#yq -i '.services.chain.environment.INITIAL_QUERY_RETRY_TIME = "60"' $HOME/namada-indexer/docker-compose.yml
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
    #echo "DATABASE_URL_TEST=\"$DATABASE_URL_TEST\""
} > "$env_file"

# copy checksums.json
cp -f $CHAINDATA_PATH/$CHAIN_ID/wasm/checksums.json $HOME/namada-indexer/checksums.json
echo "Copied $CHAINDATA_PATH/$CHAIN_ID/wasm/checksums.json"


# # restart node with read_past_height_limit adjustment
# sed -i 's#^read_past_height_limit = .*#read_past_height_limit = 360000#' $CHAINDATA_PATH/config.toml
# # echo output about the change and restart
# echo "Changed read_past_height_limit to 360000 in $CHAINDATA_PATH/config.toml, restarting node..."
# # restart the node
# sudo systemctl restart namada-node


# tear down
cd $HOME/namada-indexer
docker stop $(docker container ls --all | grep 'namada-indexer' | awk '{print $1}')
docker container rm --force $(docker container ls --all | grep 'namada-indexer' | awk '{print $1}')

if [ "$WIPE_DB" = true ]; then
        echo "Wiping the database..."
        docker compose -f docker-compose.yml down --volumes
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
        echo "Removing namada-indexer images"
        docker image rm --force $(docker image ls --all | grep -E '^namada/.*-indexer.*$' | awk '{print $3}')
        docker image rm --force $(docker image ls --all | grep '<none>' | awk '{print $3}')
    else
        echo "Not wiping the database..."
        docker compose -f docker-compose.yml down

fi


# prune all volumes (db data)
docker volume prune -fa


# build and start the containers
#curl https://sh.rustup.rs -sSf | sh -s -- -y && source "$HOME/.cargo/env" -- -y
#rustup update
#cargo install just
#just docker-up
docker compose -f $HOME/namada-indexer/docker-compose.yml --env-file $HOME/namada-indexer/.env up -d
