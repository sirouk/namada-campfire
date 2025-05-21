#!/usr/bin/env bash

# This script will stop the namada-2 node, create a snapshot using it's db contents, and restart the node

# Examples for crontab:

# campfire
# 0 */6 * * * RUN_MODE=docker CHAINDATA_PATH=$HOME/chaindata/namada-2 DOMAIN_PREFIX=testnet.campfire /root/namada-campfire/scripts/make-snapshot.sh >> /root/namada-campfire/scripts/make-snapshot.sh.log 2>&1

# housefire
# 0 */6 * * * RUN_MODE=service CHAINDATA_PATH=$HOME/.local/share/namada DOMAIN_PREFIX=testnet.housefire /root/namada-campfire/scripts/make-snapshot.sh >> /root/namada-campfire/scripts/make-snapshot.sh.log 2>&1

# mainnet 
# 0 */6 * * * RUN_MODE=service CHAINDATA_PATH=$HOME/.local/share/namada DOMAIN_PREFIX=namada /root/namada-campfire/scripts/make-snapshot.sh >> /root/namada-campfire/scripts/make-snapshot.sh.log 2>&1


# Variables
DOMAIN_PREFIX=${DOMAIN_PREFIX:-"namada"}
HTML_PATH="/usr/share/nginx/html"
DOMAIN=$(grep -oP "(?<=href=\"https://$DOMAIN_PREFIX.).*?(?=/)" "$HTML_PATH/index.html" | head -1)
export CAMPFIRE_CHAIN_DATA="$HOME/chaindata/namada-2"
export CHAINDATA_PATH=${CHAINDATA_PATH:-$CAMPFIRE_CHAIN_DATA}
export FOUND_CHAIN_ID=$(awk -F'=' '/default_chain_id/ {gsub(/[ "]/, "", $2); print $2}' "$CHAINDATA_PATH/global-config.toml")
export CHAIN_ID=${CHAIN_ID:-$FOUND_CHAIN_ID}
SNAP_TIME=$(date -u +"%Y-%m-%dT%H.%M")
SNAP_FILENAME="${CHAIN_ID}_${SNAP_TIME}.tar.lz4"
TEMP_DIR=$(mktemp -d)

# Runtime mode for managing the node process: "service" (default) or "docker"
RUN_MODE=${RUN_MODE:-"service"}
DOCKER_CONTAINER=${DOCKER_CONTAINER:-"compose-namada-2-1"}

# Step 1: Rsync db and cometbft/data while node is running
echo "Syncing live data to temporary directory..."
mkdir -p "$TEMP_DIR/db"
mkdir -p "$TEMP_DIR/cometbft/data"
rsync -a --delete --exclude='*.json' --exclude='*.toml' "$CHAINDATA_PATH/$CHAIN_ID/db/" "$TEMP_DIR/db/"
rsync -a --delete --exclude='*.json' --exclude='*.toml' "$CHAINDATA_PATH/$CHAIN_ID/cometbft/data/" "$TEMP_DIR/cometbft/data/"

# Step 2: Stop the node for final sync
echo "Stopping namada-node for final sync..."
if [ "$RUN_MODE" = "docker" ]; then
  sudo docker stop "$DOCKER_CONTAINER"
else
  sudo systemctl stop namada-node
fi

# Step 3: Final rsync to catch any incomplete files
echo "Final rsync to catch incomplete files..."
rsync -a --existing --inplace --exclude='*.json' --exclude='*.toml' "$CHAINDATA_PATH/$CHAIN_ID/db/" "$TEMP_DIR/db/"
rsync -a --existing --inplace --exclude='*.json' --exclude='*.toml' "$CHAINDATA_PATH/$CHAIN_ID/cometbft/data/" "$TEMP_DIR/cometbft/data/"

# Step 4: Start the node again
echo "Starting namada-node back up..."
if [ "$RUN_MODE" = "docker" ]; then
  sudo docker start "$DOCKER_CONTAINER"
else
  sudo systemctl start namada-node
fi

# Step 5: Create compressed snapshot (only db and cometbft/data)
echo "Creating compressed snapshot..."
sudo tar -C "$TEMP_DIR" -cf - db cometbft/data | lz4 -9 - "$HOME/$SNAP_FILENAME"

# Step 6: Remove old snapshots (older than 2 days)
echo "Removing existing snapshots older than 2 days..."
sudo find $HTML_PATH -type f -name "*.tar.lz4" -mtime +2 -exec rm -f {} \;

# Step 7: Move snapshot and update link in HTML
echo "Moving snapshot to web directory..."
sudo mv -f "$HOME/$SNAP_FILENAME" "$HTML_PATH/$SNAP_FILENAME"
echo "Updating snapshot link in HTML..."
sudo sed -i.bak -e "s|Snapshot: <a href=\".*\">Download.*</a>|Snapshot: <a href=\"https://$DOMAIN_PREFIX.$DOMAIN/$SNAP_FILENAME\">Download</a>|" "$HTML_PATH/index.html"

# Step 8: Cleanup temporary directory
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

echo "Snapshot completed successfully!"
