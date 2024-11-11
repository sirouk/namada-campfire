#!/bin/bash


export NAMADA_TAG=v0.45.1
export PUBLIC_IP=192.64.82.62
export CHAIN_PREFIX="namada"
export BLOCK_SECONDS="6s"
export NAMADA_GENESIS_TX_CHAIN_ID="$CHAIN_PREFIX"


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

# Pip packages
python3 -m pip install toml --upgrade


# Firewall
sudo ufw allow 22
sudo ufw allow 26656
sudo ufw allow 26660
sudo ufw allow 26659
sudo ufw allow 26657


# Install namada and build wasm
mkdir -p $HOME/.namada-shared/wasm/
mkdir -p $HOME/.namada-shared/wasm-build/

# checkout and build the specified tag of Namada binaries
cd $HOME/.namada-shared/wasm-build
git clone https://github.com/anoma/namada.git
cd $HOME/.namada-shared/wasm-build/namada
git fetch --all --tags
git checkout tags/${NAMADA_TAG}

# Install namada
make build && make install
rustup update

    # # in case the binaries are not copied over, copy from ./target/release to ~/.cargo/bin
    # find ~/namada/target/release -type f -executable -name 'namada*' ! -name '*.d' -exec cp -f {} ~/.cargo/bin/ \;

# check namada version
namada --version
# should be Namada v0.43.0

# check go version
protoc --version
#It should output at least:
# libprotoc 3.12.4

sleep 10;

# CometBFT v0.37.9 recommended as of 2024-07-26
mkdir cd $HOME/.namada-shared/wasm-build/cometbft
cd cd $HOME/.namada-shared/wasm-build/cometbft
wget https://github.com/cometbft/cometbft/releases/download/v0.37.9/cometbft_0.37.9_linux_amd64.tar.gz -O cometbft_0.37.9_linux_amd64.tar.gz
tar -xvf cometbft_0.37.9_linux_amd64.tar.gz
sudo cp -f cometbft /usr/local/bin/
cometbft version
# should be cometbft 0.37.9


# prepare wasm build environment
mkdir $HOME/.namada-shared/wasm-build/binaryen
cd $HOME/.namada-shared/wasm-build/binaryen
wget https://github.com/WebAssembly/binaryen/releases/download/version_116/binaryen-version_116-x86_64-linux.tar.gz -O binaryen-version_116-x86_64-linux.tar.gz
tar -xvf binaryen-version_116-x86_64-linux.tar.gz
cp $HOME/.namada-shared/wasm-build/binaryen/binaryen-version_116/bin/* /usr/local/bin;


# build the wasm files
cd $HOME/.namada-shared/wasm-build/namada
make build-release
rustup target add wasm32-unknown-unknown
make build-wasm-scripts

# copy namada and cometbft binaries, and wasm files
cp $HOME/.namada-shared/wasm-build/namada/wasm/*.wasm $HOME/.namada-shared/wasm/
cp $HOME/.namada-shared/wasm-build/namada/wasm/*.json $HOME/.namada-shared/wasm/


echo "Generating chain configs..."

# grab the genesis files
cd $HOME
git clone https://github.com/anoma/namada-mainnet-genesis -b brent/dry-run
cd ./namada-mainnet-genesis
# make sure we are in the right branch
git branch
# brent/dry-run


mkdir -p $HOME/.namada-shared/genesis
cp -f ~/namada-mainnet-genesis/genesis/balances.toml $HOME/.namada-shared/genesis/balances.toml
cp -f ~/namada-mainnet-genesis/genesis/parameters.toml $HOME/.namada-shared/genesis/parameters.toml
cp -f ~/namada-mainnet-genesis/genesis/tokens.toml $HOME/.namada-shared/genesis/tokens.toml
cp -f ~/namada-mainnet-genesis/genesis/transactions.toml $HOME/.namada-shared/genesis/transactions.toml
cp -f ~/namada-mainnet-genesis/genesis/validity-predicates.toml $HOME/.namada-shared/genesis/validity-predicates.toml

# add genesis transactions to transactions.toml
# TODO: move to python script
#cat $HOME/.namada-shared/namada-1/transactions.toml >> $HOME/.namada-shared/genesis/transactions.toml
#cat $HOME/.namada-shared/namada-3/transactions.toml >> $HOME/.namada-shared/genesis/transactions.toml
#cat $HOME/.namada-shared/$STEWARD_ALIAS/transactions.toml >> $HOME/.namada-shared/genesis/transactions.toml
#cat $HOME/.namada-shared/$FAUCET_ALIAS/transactions.toml >> $HOME/.namada-shared/genesis/transactions.toml

# append all the submitted transactions.tomls in the 'submitted' directory
# for file in /genesis/submitted/*; do
#   echo "" >> $HOME/.namada-shared/genesis/transactions.toml # ensure newline
#   cat "$file" >> $HOME/.namada-shared/genesis/transactions.toml
# done

#python3 /scripts/make_balances.py $HOME/.namada-shared /genesis/balances.toml $SELF_BOND_AMT > $HOME/.namada-shared/genesis/balances.toml

echo "Genesis balances preview:"
head -n10 $HOME/.namada-shared/genesis/balances.toml
echo "..."
tail -n10 $HOME/.namada-shared/genesis/balances.toml
echo ""

# add steward address to parameters.toml
#sed -i "s#STEWARD_ADDR#$steward_address#g" $HOME/.namada-shared/genesis/parameters.toml

# extract the tx and vp checksums from the checksums.json file
TX_CHECKSUMS=$(jq -r 'to_entries[] | select(.key | startswith("tx")) | .value' $HOME/.namada-shared/wasm/checksums.json | sed 's/.*\.\(.*\)\..*/"\1"/' | paste -sd "," -)
VP_CHECKSUMS=$(jq -r 'to_entries[] | select(.key | startswith("vp")) | .value' $HOME/.namada-shared/wasm/checksums.json | sed 's/.*\.\(.*\)\..*/"\1"/' | paste -sd "," -)

# add them to parameters.toml whitelist
sed -i "s#tx_whitelist = \[\]#tx_whitelist = [$TX_CHECKSUMS]#" ~/.namada-shared/genesis/parameters.toml
sed -i "s#vp_whitelist = \[\]#vp_whitelist = [$VP_CHECKSUMS]#" ~/.namada-shared/genesis/parameters.toml

# add a random word to the chain prefix for human readability
#RANDOM_WORD=$(shuf -n 1 /root/words)
RANDOM_WORD="dryrun"
FULL_PREFIX="${CHAIN_PREFIX}-${RANDOM_WORD}"

# create the chain configs
#GENESIS_TIME=$(date -u -d "+$GENESIS_DELAY_MINS minutes" +"%Y-%m-%dT%H:%M:%S.000000000+00:00")
GENESIS_TIME="2024-11-12T15:00:00.000000000+00:00"
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


# serve config tar over http
echo "Serving configs..."
mkdir -p $HOME/.namada-shared/serve
cp *.tar.gz $HOME/.namada-shared/serve

echo "Starting the server for configs..."
pm2 stop namada-config-server
pm2 delete namada-config-server
pm2 start "python3 -m http.server --directory $HOME/.namada-shared/serve 8082" --name "namada-config-server"
pm2 save --force


while [ ! -f "$HOME/.namada-shared/chain.config" ]; do
  # write config server info to shared volume
  echo "Waiting for chain.config to be created..."
  sleep 2
fi
printf "%b\n%b" "$PUBLIC_IP" "$CHAIN_ID" | tee $HOME/.namada-shared/chain.config


while [ ! -f "$HOME/.namada-shared/chain.config" ]; do
  echo "Configs server info not ready. Sleeping for 5s..."
  sleep 5
done
echo "Configs server info found, proceeding with network setup"


export CHAIN_ID=$(awk 'NR==2' $HOME/.namada-shared/chain.config)
echo "Namada chain ready! ID: $CHAIN_ID"