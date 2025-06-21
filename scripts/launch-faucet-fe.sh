#!/usr/bin/env bash


# Examples:
    # Mainnet and Housefire:
    # CHAINDATA_PATH=$BASE_DIR $HOME/namada-campfire/scripts/launch-faucet-fe.sh

    # Campfire
    # CHAINDATA_PATH=$HOME/chaindata/namada-1 $HOME/namada-campfire/scripts/launch-faucet-fe.sh


### Grab the repo
rm -rf $HOME/namada-interface
cd $HOME
#git clone -b v0.1.0-0e77e71 https://github.com/anoma/namada-interface.git
git clone -b main https://github.com/anoma/namada-interface.git


# Copy over the files for docker and nginx
#cp -f $HOME/namada-campfire/docker/container-build/faucet-frontend/Dockerfile $HOME/namada-interface/Dockerfile
mkdir -p $HOME/namada-interface/apps/faucet/docker
cp -f $HOME/namada-campfire/docker/container-build/faucet-frontend/nginx.conf $HOME/namada-interface/apps/faucet/docker/nginx.conf


# Prepare the environment variables
#export CHAIN_ID=$(awk -F'=' '/default_chain_id/ {gsub(/[ "]/, "", $2); print $2}' "$HOME/chaindata/namada-1/global-config.toml")

export CAMPFIRE_CHAIN_DATA="$HOME/chaindata/namada-1"
export CHAINDATA_PATH=${CHAINDATA_PATH:-$CAMPFIRE_CHAIN_DATA}

export FOUND_CHAIN_ID=$(awk -F'=' '/default_chain_id/ {gsub(/[ "]/, "", $2); print $2}' "$CHAINDATA_PATH/global-config.toml")
export CHAIN_ID=${CHAIN_ID:-$FOUND_CHAIN_ID}
export NAM=$(awk '/\[addresses\]/ {found=1} found && /nam = / {gsub(/.*= "/, ""); sub(/"$/, ""); print; exit}' "$CHAINDATA_PATH/$CHAIN_ID/wallet.toml")
#export FAUCET_ADDRESS=$(awk '/\[addresses\]/ {found=1} found && /faucet-1 = / {gsub(/.*= "/, ""); sub(/"$/, ""); sub(/unencrypted:/, ""); print; exit}' "$CHAINDATA_PATH/$CHAIN_ID/wallet.toml")
# Fetch the faucet private key
#export CHAIN_ID=$(awk -F'=' '/default_chain_id/ {gsub(/[ "]/, "", $2); print $2}' "$HOME/chaindata/namada-1/global-config.toml")
echo "CHAIN_ID=$CHAIN_ID"



# to get our $DOMAIN
source $HOME/*.env

# write env file
env_file=$HOME/namada-interface/apps/faucet/.env
{

    # for v0.1.0-0e77e71: as documented in: namada-campfire/docker/container-build/faucet-frontend/README.md
    #echo "REACT_APP_FAUCET_API_URL=https://api.faucet.$DOMAIN"
    #echo "REACT_APP_FAUCET_API_ENDPOINT=/api/v1/faucet"
    #echo "REACT_APP_FAUCET_LIMIT=1000"
    #echo "REACT_APP_TOKEN_NAM=$NAM"

    # for main branch:
    echo "NAMADA_INTERFACE_FAUCET_API_URL=https://api.faucet.$DOMAIN"
    echo "NAMADA_INTERFACE_FAUCET_API_ENDPOINT=/api/v1/faucet"
    #echo "NAMADA_INTERFACE_FAUCET_LIMIT=1000"
    #echo "NAMADA_INTERFACE_PROXY_PORT=9000"
    #echo "NAMADA_INTERFACE_NAMADA_TOKEN=$NAM"
    
    # for main branch:
    #echo "INDEXER_URL=https://indexer.$DOMAIN:443"
    #echo "RPC_URL=https://rpc.$DOMAIN:443"
    #echo "CHAIN_ID=$CHAIN_ID"

} > "$env_file"


# source the env before building
source $env_file


# This is a template file for Namadillo config.
# Rename this file to namadillo.config.toml (removing the initial dot) in order to copy it into the Docker container
#indexer_url = ""
#rpc_url = ""
#cp -f $HOME/namada-interface/docker/.namadillo.config.toml $HOME/namada-interface/docker/namadillo.config.toml
echo "indexer_url = \"https://indexer.$DOMAIN:443\"" >> $HOME/namada-interface/docker/namadillo.config.toml
echo "rpc_url = \"https://rpc.$DOMAIN:443\"" >> $HOME/namada-interface/docker/namadillo.config.toml


# Tear down any conatiners, remove them and their images
docker stop $(docker container ls --all | grep 'faucet-fe' | awk '{print $1}')
docker container rm --force $(docker container ls --all | grep 'faucet-fe' | awk '{print $1}')
if [ -z "${LOGS_NOFOLLOW}" ]; then
    docker image rm --force $(docker image ls --all | grep 'faucet-fe' | awk '{print $3}')
fi

# Build
cp -rf $HOME/namada-interface/docker/faucet/Dockerfile $HOME/namada-interface/
cd $HOME/namada-interface

# clearn build cache for this build
#docker builder prune -f --all

# build with a specified env file no cache
docker build -t faucet-fe:local .


# Start the faucet frontend
cd $HOME/namada-interface
docker run --name faucet-fe -d -p "4000:80" faucet-fe:local


if [ -z "${LOGS_NOFOLLOW}" ]; then
    echo "**************************************************************************************"
    echo "Following faucet frontend logs, feel free to press Ctrl+C to exit!"
    docker logs -f $(docker container ls --all | grep faucet-fe | awk '{print $1}')
fi