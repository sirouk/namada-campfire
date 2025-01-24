#!/usr/bin/env bash


# Grab the repo
rm -rf $HOME/namada-masp-indexer
cd $HOME
git clone https://github.com/anoma/namada-masp-indexer.git
cd $HOME/namada-masp-indexer
git fetch --all
#git checkout master
#git pull

# Get the latest tag
LATEST_TAG=$(git describe --tags $(git rev-list --tags --max-count=1))
git checkout $LATEST_TAG
git reset --hard $LATEST_TAG
git pull

# Copy the docker compose file: namada-campfire/docker/compose/docker-compose-namada-masp-indexer.yml
#cp -f $HOME/namada-campfire/docker/compose/docker-compose-namada-masp-indexer.yml $HOME/namada-masp-indexer/docker-compose.yml

# prep vars
#export POSTGRES_PORT="5433"
#export DATABASE_URL="postgres://postgres:password@postgres:$POSTGRES_PORT/masp_indexer_local"
#export DATABASE_URL="postgres://postgres:password@0.0.0.0:$POSTGRES_PORT/masp_indexer_local"
export TENDERMINT_URL=${TENDERMINT_URL:-"http://172.17.0.1:26657"}

#export WEBSERVER_PORT="5000"
#export PORT="$WEBSERVER_PORT"

# output vars to .env in root of namada-masp-indexer
env_file="$HOME/namada-masp-indexer/.env"
{
    #echo "DATABASE_URL=\"$DATABASE_URL\""
    echo "COMETBFT_URL=\"$TENDERMINT_URL\""
    #echo "PORT=\"$WEBSERVER_PORT\""
    #echo "DATABASE_URL_TEST=\"$DATABASE_URL_TEST\""
} > "$env_file"

# Load vars
source $env_file


cd $HOME/namada-masp-indexer

# tear down
docker compose -f docker-compose.yml down --volumes
docker stop $(docker container ls --all | grep 'namada-masp-' | awk '{print $1}')
docker container rm --force $(docker container ls --all | grep 'namada-masp-' | awk '{print $1}')

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

if [ -z "${LOGS_NOFOLLOW}" ]; then
    docker image rm --force $(docker image ls --all | grep 'namada-masp-' | awk '{print $3}')
fi

# prune all volumes (db data)
docker volume prune -fa

# start up
docker compose -f $HOME/namada-masp-indexer/docker-compose.yml --env-file $env_file up -d