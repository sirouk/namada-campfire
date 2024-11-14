#!/usr/bin/env bash

# Run this script after the chain is running to write the namada-interface .env file, rebuild and start the container.
# Note: as this rebuilds the container it takes some time to complete
REPO_NAME="namada-interface"
REPO_DIR="$HOME/$REPO_NAME"
INTERFACE_DIR="apps/namadillo"


### Grab the repo
rm -rf ~/namada-interface
cd $HOME
#git clone -b v0.1.0-0e77e71 https://github.com/anoma/namada-interface.git
git clone https://github.com/anoma/$REPO_NAME.git

#cd $HOME/namada-interface && git checkout 1ed4d1285ffbf654c84a80353537023ba98e0614
cd $REPO_DIR && git fetch --all && git checkout main && git pull

# test commit with chain phase ungating features
git checkout 91332b30e88e4844b86fc95be2b598e79a80222f

cp -f $HOME/namada-campfire/docker/container-build/namada-interface/Dockerfile $REPO_DIR/Dockerfile-interface
#cp -f $REPO_DIR/docker/namadillo/Dockerfile $REPO_DIR/Dockerfile-interface # needs help with writing the config
#cp -f $HOME/namada-campfire/docker/container-build/namada-interface/nginx.conf $REPO_DIR/nginx.conf


export CAMPFIRE_CHAIN_DATA="$HOME/chaindata/namada-1"
export CHAINDATA_PATH=${CHAINDATA_PATH:-$CAMPFIRE_CHAIN_DATA}

export FOUND_CHAIN_ID=$(awk -F'=' '/default_chain_id/ {gsub(/[ "]/, "", $2); print $2}' "$CHAINDATA_PATH/global-config.toml")
export CHAIN_ID=${CHAIN_ID:-$FOUND_CHAIN_ID}
export NAM=$(awk '/\[addresses\]/ {found=1} found && /nam = / {gsub(/.*= "/, ""); sub(/"$/, ""); print; exit}' "$CHAINDATA_PATH/$CHAIN_ID/wallet.toml")
#export FAUCET_ADDRESS=$(awk '/\[addresses\]/ {found=1} found && /faucet-1 = / {gsub(/.*= "/, ""); sub(/"$/, ""); sub(/unencrypted:/, ""); print; exit}' "$CHAINDATA_PATH/$CHAIN_ID/wallet.toml")


# Load Campfire vars in environment
source $HOME/campfire.env

# write env file
env_file="$REPO_DIR/$INTERFACE_DIR/.env"
{
    echo "NODE_ENV=development"
    echo "NAMADA_INTERFACE_LOCAL=false"

    echo "NAMADA_INTERFACE_NAMADA_ALIAS=Namada Dry Run"
    echo "NAMADA_INTERFACE_NAMADA_TOKEN=$NAM"
    echo "NAMADA_INTERFACE_NAMADA_CHAIN_ID=$CHAIN_ID"
    echo "NAMADA_INTERFACE_NAMADA_URL=https://rpc.$DOMAIN:443"
    echo "RPC_URL=https://rpc.$DOMAIN:443" # used for bootstrap_config.sh
    
    echo "NAMADA_INTERFACE_NAMADA_BECH32_PREFIX=tnam"
    echo "NAMADA_INTERFACE_INDEXER_URL=https://indexer.$DOMAIN:443"
    echo "INDEXER_URL=https://indexer.$DOMAIN:443" # used for bootstrap_config.sh

    echo "MASP_INDEXER_URL=https://masp.$DOMAIN:443" # used for bootstrap_config.sh

    # echo "REACT_APP_NAMADA_FAUCET_ADDRESS=\"$FAUCET_ADDRESS\""
    # echo "NAMADA_INTERFACE_NAMADA_FAUCET_ADDRESS=\"$FAUCET_ADDRESS\""
    # echo "NAMADA_INTERFACE_NAMADA_FAUCET_LIMIT=1000"

} > "$env_file"


# This was the template file for Namadillo config.
#cp -f $REPO_DIR/docker/.namadillo.config.toml $REPO_DIR/docker/namadillo.config.toml

# This is the template file for Namadillo config.
# write config file
config_file="$REPO_DIR/$INTERFACE_DIR/public/config.toml"
{
    echo "indexer_url = https://indexer.$DOMAIN:443"
    echo "rpc_url = https://rpc.$DOMAIN:443"
    echo "masp_indexer_url = https://masp.$DOMAIN:443"
} > "$config_file"


# load Namadillo env vars, build, and run
source $env_file

if [ -n "${LOGS_NOFOLLOW}" ]; then
    docker stop $(docker container ls --all | grep 'interface' | awk '{print $1}')
    docker container rm --force $(docker container ls --all | grep 'interface' | awk '{print $1}')
    docker image rm --force $(docker image ls --all | grep 'interface' | awk '{print $3}')
fi

docker build -f $REPO_DIR/Dockerfile-interface --build-arg INDEXER_URL="$INDEXER_URL" --build-arg RPC_URL="$RPC_URL" --build-arg MASP_INDEXER_URL="$MASP_INDEXER_URL" -t interface:local $REPO_DIR

docker stop $(docker container ls --all | grep 'interface' | awk '{print $1}')
docker container rm --force $(docker container ls --all | grep 'interface' | awk '{print $1}')

docker run --name interface -d --env-file $env_file -p "3000:80" interface:local


if [ -z "${LOGS_NOFOLLOW}" ]; then
    echo "**************************************************************************************"
    echo "Following interface logs, feel free to press Ctrl+C to exit!"
    docker logs -f $(docker container ls --all | grep interface | awk '{print $1}')
fi