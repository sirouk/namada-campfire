#!/bin/bash

export GENESIS_TIME="2024-11-12T15:00:00.000000000+00:00"
export NAMADA_TAG=v0.45.1
export CHAIN_PREFIX="namada"
export CHAIN_SUFFIX="dryrun"
unset NAMADA_GENESIS_TX_CHAIN_ID
export BLOCK_SECONDS="6s"
export EXTIP=74.50.93.254
export SERVE_PORT=8082


sudo apt update && sudo apt upgrade -y

# some basic tools
sudo apt install -y curl git wget jq make gcc nano tmux htop clang bsdmainutils ncdu unzip tar

# from namada docs
sudo apt install -y make git-core libssl-dev pkg-config libclang-12-dev build-essential protobuf-compiler clang-tools-11

# missing from namada docs
sudo apt install -y libudev-dev

# cleanup packages
sudo apt autoremove && sudo apt autoclean

# install rust
curl https://sh.rustup.rs -sSf | sh -s -- -y && source "$HOME/.cargo/env" -- -y
rustup update

# Pip packages
python3 -m pip install toml --upgrade


# Install pm2
if command -v pm2 &> /dev/null
then
    echo "PM2 is installed. Proceeding with PM2 commands."
    pm2 startup && pm2 save --force
else
    echo "PM2 is not installed. Installing PM2 and setting it up."
    sudo apt install jq npm -y
    sudo npm install pm2 -g && pm2 update
    # make pm2 and processes survive reboot
    npm install pm2@latest -g && pm2 update && pm2 save --force && pm2 startup && pm2 save
fi


# Firewall
sudo ufw allow 22
sudo ufw allow 26656
sudo ufw allow 26660
sudo ufw allow 26659
sudo ufw allow 26657


# Prepare directories
mkdir -p $HOME/.namada-shared/wasm/
mkdir -p $HOME/.namada-shared/wasm-build/


# Install namada binaries
cd $HOME/.namada-shared/wasm-build
git clone https://github.com/anoma/namada.git
cd $HOME/.namada-shared/wasm-build/namada
git fetch --all --tags
git checkout tags/${NAMADA_TAG}
git clean -xdf

namada_version=$(namada --version)
if [[ $namada_version == "Namada ${NAMADA_TAG}" ]]; then
  echo "Namada ${NAMADA_TAG} is already installed"
else
    # echo "Building Namada v${NAMADA_TAG}"
    # rm -rf $HOME/.cargo/bin/namada*
    # rm -rf $HOME/usr/local/bin/namada*
    # make build-release
    # make install

    echo "Fetching Namada ${NAMADA_TAG}"
    cd $HOME/.namada-shared/wasm-build
    # LAST FROM: https://github.com/anoma/namada/releases/tag/v0.45.1
    wget https://github.com/anoma/namada/releases/download/$NAMADA_TAG/namada-$NAMADA_TAG-Linux-x86_64.tar.gz -O namada-$NAMADA_TAG-Linux-x86_64.tar.gz
    tar -xvf namada-$NAMADA_TAG-Linux-x86_64.tar.gz
    cd namada-$NAMADA_TAG-Linux-x86_64.tar.gz
    mkdir -p $HOME/.cargo/bin/
    cp -rf ./namada* $HOME/.cargo/bin/
fi

# check namada version
which namada
namada --version
# should be Namada v0.45.1

# check go version
protoc --version
#It should output at least:
# libprotoc 3.12.4

sleep 5;


# CometBFT v0.37.11
cometbft_version=$(cometbft version)
if [[ $cometbft_version == "0.37.11" ]]; then
    echo "CometBFT 0.37.11 is already installed"
else
    echo "Installing CometBFT 0.37.11"
    mkdir cd $HOME/.namada-shared/wasm-build/cometbft
    cd cd $HOME/.namada-shared/wasm-build/cometbft
    wget https://github.com/cometbft/cometbft/releases/download/v0.37.11/cometbft_0.37.11_linux_amd64.tar.gz -O cometbft_0.37.11_linux_amd64.tar.gz
    tar -xvf cometbft_0.37.11_linux_amd64.tar.gz
    sudo cp -rf cometbft /usr/local/bin/
fi
cometbft version
# should be cometbft 0.37.11


# prepare wasm build environment
mkdir $HOME/.namada-shared/wasm-build/binaryen
cd $HOME/.namada-shared/wasm-build/binaryen
wget https://github.com/WebAssembly/binaryen/releases/download/version_116/binaryen-version_116-x86_64-linux.tar.gz -O binaryen-version_116-x86_64-linux.tar.gz
tar -xvf binaryen-version_116-x86_64-linux.tar.gz
cp -rf $HOME/.namada-shared/wasm-build/binaryen/binaryen-version_116/bin/* /usr/local/bin;


# build the wasm files
cd $HOME/.namada-shared/wasm-build/
# git clean -xdf
# make build-release
# rustup target add wasm32-unknown-unknown
# make build-wasm-scripts
# cp -rf $HOME/.namada-shared/wasm-build/namada/wasm/*.wasm $HOME/.namada-shared/wasm/
# cp -rf $HOME/.namada-shared/wasm-build/namada/wasm/*.json $HOME/.namada-shared/wasm/

# # download the wasm artifacts
# LAST FROM: https://github.com/anoma/namada/actions/runs/11725915041/job/32663331838
echo "Please provide the URL to the prebuilt-wasm.zip file from the Namada CI artifacts"
read WASM_URL_FROM_GITHUB
# NOTE: ^^^ must be logged in to grab this and the url will be different
mkdir $HOME/.namada-shared/wasm-build/prebuilt-wasm/
cd $HOME/.namada-shared/wasm-build/prebuilt-wasm/
wget $WASM_URL_FROM_GITHUB -O prebuilt-wasm.zip
# LAST FROM: https://github.com/anoma/namada/actions/runs/11725915041/artifacts/2158408260
unzip prebuilt-wasm.zip
rm -f prebuilt-wasm.zip


# Ensure fresh slate and copy over wasm files and checksum.json
rm -rf $HOME/.namada-shared/wasm/*
cp -rf $HOME/.namada-shared/wasm-build/prebuilt-wasm/*.wasm $HOME/.namada-shared/wasm/
cp -rf $HOME/.namada-shared/wasm-build/prebuilt-wasm/*.json $HOME/.namada-shared/wasm/


echo "Generating chain configs..."

# grab the genesis files
cd $HOME/.namada-shared/
git clone https://github.com/anoma/namada-mainnet-genesis -b brent/dry-run
# make sure we are in the right branch
cd $HOME/.namada-shared/namada-mainnet-genesis
git branch
# brent/dry-run

# Copy the genesis files
mkdir -p $HOME/.namada-shared/genesis
cp -rf $HOME/.namada-shared/namada-mainnet-genesis/genesis/balances.toml $HOME/.namada-shared/genesis/balances.toml
cp -rf $HOME/.namada-shared/namada-mainnet-genesis/genesis/parameters.toml $HOME/.namada-shared/genesis/parameters.toml
cp -rf $HOME/.namada-shared/namada-mainnet-genesis/genesis/tokens.toml $HOME/.namada-shared/genesis/tokens.toml
cp -rf $HOME/.namada-shared/namada-mainnet-genesis/genesis/transactions.toml $HOME/.namada-shared/genesis/transactions.toml
cp -rf $HOME/.namada-shared/namada-mainnet-genesis/genesis/validity-predicates.toml $HOME/.namada-shared/genesis/validity-predicates.toml


echo "Genesis balances preview:"
head -n10 $HOME/.namada-shared/genesis/balances.toml
echo "..."
tail -n10 $HOME/.namada-shared/genesis/balances.toml
echo ""

# extract the tx and vp checksums from the checksums.json file
TX_CHECKSUMS=$(jq -r 'to_entries[] | select(.key | startswith("tx")) | .value' $HOME/.namada-shared/wasm/checksums.json | sed 's/.*\.\(.*\)\..*/"\1"/' | paste -sd "," -)
VP_CHECKSUMS=$(jq -r 'to_entries[] | select(.key | startswith("vp")) | .value' $HOME/.namada-shared/wasm/checksums.json | sed 's/.*\.\(.*\)\..*/"\1"/' | paste -sd "," -)

# add them to parameters.toml whitelist
sed -i "s#tx_allowlist = \[\]#tx_allowlist = [$TX_CHECKSUMS]#" $HOME/.namada-shared/genesis/parameters.toml
sed -i "s#vp_allowlist = \[\]#vp_allowlist = [$VP_CHECKSUMS]#" $HOME/.namada-shared/genesis/parameters.toml

# add a random word to the chain prefix for human readability
#RANDOM_WORD=$(shuf -n 1 /root/words)
RANDOM_WORD="${CHAIN_SUFFIX}"
FULL_PREFIX="${CHAIN_PREFIX}-${RANDOM_WORD}"

# create the chain configs
#GENESIS_TIME=$(date -u -d "+$GENESIS_DELAY_MINS minutes" +"%Y-%m-%dT%H:%M:%S.000000000+00:00")
# ^ set above statically
INIT_OUTPUT=$(namadac utils init-network \
  --genesis-time "$GENESIS_TIME" \
  --wasm-checksums-path $HOME/.namada-shared/wasm/checksums.json \
  --wasm-dir $HOME/.namada-shared/wasm \
  --chain-prefix $FULL_PREFIX \
  --templates-path $HOME/.namada-shared/genesis \
  --consensus-timeout-commit ${BLOCK_SECONDS})

echo "$INIT_OUTPUT"
CHAIN_ID=$(echo "$INIT_OUTPUT" \
  | grep 'Derived chain ID:' \
  | awk '{print $4}')
echo "Chain id: $CHAIN_ID"


# serve config tar over http
echo "Serving configs..."
mkdir -p $HOME/.namada-shared/serve
rm -rf $HOME/.namada-shared/serve/*
cp *.tar.gz $HOME/.namada-shared/serve

echo "Starting the server for configs..."
pm2 stop namada-config-server
pm2 delete namada-config-server
pm2 start "python3 -m http.server --directory $HOME/.namada-shared/serve 8082" --name "namada-config-server"
pm2 save --force


printf "%b\n%b" "$EXTIP" "$CHAIN_ID" | tee $HOME/.namada-shared/chain.config
#export CHAIN_ID=$(awk 'NR==2' $HOME/.namada-shared/chain.config)


echo "Updating Config for landing page..."
NODE_ID=$(cometbft show-node-id --home $HOME/.local/share/namada/$CHAIN_ID/cometbft/ | awk '{last_line = $0} END {print last_line}')

# fetch domain info
HTML_PATH="/usr/share/nginx/html"
DOMAIN=$(grep -oP '(?<=href="https://testnet.).*?(?=/)' "$HTML_PATH/index.html" | head -1)


# Write content to $CHAIN_PREFIX.env
ENV_FILENAME="/usr/share/nginx/html/$CHAIN_PREFIX.env"
rm -f $ENV_FILENAME
PEERS="\"tcp://$NODE_ID@${EXTIP}:${P2P_PORT:-26656}\""
echo "CHAIN_ID=$CHAIN_ID" > $ENV_FILENAME
echo "#EXTIP=" >> $ENV_FILENAME
echo "CONFIGS_SERVER=https://testnet.$DOMAIN/configs" >> $ENV_FILENAME
echo "PERSISTENT_PEERS=$PEERS" >> $ENV_FILENAME

cp $HOME/namada-campfire/docker/config/local-namada/index.html /usr/share/nginx/html/index.html
sed -i "s/CHAIN_ID/$CHAIN_ID/g" /usr/share/nginx/html/index.html
sed -i "s/NAMADA_TAG/$NAMADA_TAG/g" /usr/share/nginx/html/index.html
sed -i "s/DOMAIN/$DOMAIN/g" /usr/share/nginx/html/index.html
sed -i "s/CHAIN_PREFIX/$CHAIN_PREFIX/g" /usr/share/nginx/html/index.html
sed -i "s#PEER#$PEERS#g" /usr/share/nginx/html/index.html

rm -rf /usr/share/nginx/html/wasm.tar.gz
tar -czf /usr/share/nginx/html/wasm.tar.gz $HOME/.namada-shared/wasm


echo "Namada chain ready! ID: $CHAIN_ID"