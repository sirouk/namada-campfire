#!/bin/bash

source $HOME/housefire.env

    # NAMADA_TAG=v1.0.0
    # COMETBFT_VER=0.37.11
    # CHAIN_PREFIX=housefire
    # EXTIP=74.50.93.254
    # P2P_PORT=26656
    # RPC_PORT=26657
    # SELF_BOND_AMT=1
    # GENESIS_DELAY_MINS=1
    # DOMAIN=housefire.tududes.com
    # NAMADA_NETWORK_CONFIGS_SERVER="https://github.com/vknowable/namada-campfire/releases/download/housefire-alpaca"


# extract info from configs
export BASE_DIR=${BASE_DIR:-$HOME/.local/share/namada}
export CAMPFIRE_CHAIN_DATA="$HOME/chaindata/namada-1"
export CHAINDATA_PATH=${CHAINDATA_PATH:-$CAMPFIRE_CHAIN_DATA}
export FOUND_CHAIN_ID=$(awk -F'=' '/default_chain_id/ {gsub(/[ "]/, "", $2); print $2}' "$CHAINDATA_PATH/../global-config.toml")
export CHAIN_ID=${CHAIN_ID:-$FOUND_CHAIN_ID}
echo "Proceeding with CHAIN_ID: $CHAIN_ID"

# extract peers
NODE_ID=$(cometbft show-node-id --home $HOME/.local/share/namada/$CHAIN_ID/cometbft/ | awk '{last_line = $0} END {print last_line}')
PERSISTENT_PEERS="\"tcp://$NODE_ID@${EXTIP}:${P2P_PORT:-26656}\""

# Write content to $CHAIN_PREFIX.env
ENV_FILENAME="/usr/share/nginx/html/$CHAIN_PREFIX.env"
cp -f $HOME/$CHAIN_PREFIX.env $ENV_FILENAME
echo "CHAIN_ID=$CHAIN_ID" >> $ENV_FILENAME
echo "PERSISTENT_PEERS=$PERSISTENT_PEERS" >> $ENV_FILENAME


echo "Updating Config for landing page..."
export HTML_PATH="/usr/share/nginx/html/index.html"
cp -f $HOME/namada-campfire/html/index-housefire.html $HTML_PATH

# Update the HTML file
sed -i "s#https://testnet.DOMAIN/CHAIN_ID.tar.gz#$NAMADA_NETWORK_CONFIGS_SERVER/$CHAIN_ID.tar.gz#g" $HTML_PATH
sed -i "s#https://testnet.DOMAIN/configs#$NAMADA_NETWORK_CONFIGS_SERVER#g" $HTML_PATH
sed -i "s/CHAIN_ID/$CHAIN_ID/g" $HTML_PATH
sed -i "s/NAMADA_TAG/$NAMADA_TAG/g" $HTML_PATH
sed -i "s/DOMAIN/$DOMAIN/g" $HTML_PATH
sed -i "s/CHAIN_PREFIX/$CHAIN_PREFIX/g" $HTML_PATH
sed -i "s#PEER#$PERSISTENT_PEERS#g" $HTML_PATH


# compress the directory /root/.local/share/namada/housefire-alpaca.cc0d3e0c033be/wasm as wasm.tar.gz
tar -czf /usr/share/nginx/html/wasm.tar.gz -C $HOME/.local/share/namada/$CHAIN_ID/ wasm

# make the first snapshot
DOMAIN_PREFIX="testnet.$CHAIN_PREFIX" CHAINDATA_PATH=$BASE_DIR/$CHAIN_ID $HOME/namada-campfire/scripts/make-snapshot.sh
