#!/usr/bin/env bash

# This script will stop the namada-2 node, create a snapshot using it's db contents, and restart the node

# Example for crontab:
# 0 */6 * * * RUN_MODE=docker DOMAIN_PREFIX=testnet.campfire /root/namada-campfire/scripts/make-snapshot.sh >> /root/namada-campfire/scripts/make-snapshot.sh.log 2>&1
# or 
# 0 */6 * * * RUN_MODE=service DOMAIN_PREFIX=testnet.campfire /root/namada-campfire/scripts/make-snapshot.sh >> /root/namada-campfire/scripts/make-snapshot.sh.log 2>&1

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

# Runtime mode for managing the node process: "service" (default) or "docker"
RUN_MODE=${RUN_MODE:-"service"}
DOCKER_CONTAINER=${DOCKER_CONTAINER:-"compose-namada-2-1"}

# Temporary working directory for snapshot build
WORK_DIR=$(mktemp -d)
DEST_DIR="$WORK_DIR/$CHAIN_ID"
mkdir -p "$DEST_DIR"

echo "Initial data sync (node stays online)...(temp dir: $DEST_DIR)"
rsync -a --delete "$CHAINDATA_PATH/$CHAIN_ID/" "$DEST_DIR/"

echo "Stopping namada-node for final sync..."
if [ "$RUN_MODE" = "docker" ]; then
  sudo docker stop "$DOCKER_CONTAINER"
else
  sudo systemctl stop namada-node
fi

echo "Final data sync (should be quick)..."
rsync -a --delete "$CHAINDATA_PATH/$CHAIN_ID/" "$DEST_DIR/"

echo "Starting namada-node back up..."
if [ "$RUN_MODE" = "docker" ]; then
  sudo docker start "$DOCKER_CONTAINER"
else
  sudo systemctl start namada-node
fi

echo "Creating compressed snapshot..."
# Use multi-threaded LZ4 for faster compression
sudo tar -C "$WORK_DIR" -cf - "$CHAIN_ID" | lz4 -9 - "$HOME/$SNAP_FILENAME"

echo "Removing existing snapshots older than ..."
# remove snapshots only older than 2 days
sudo find $HTML_PATH -type f -name "*.tar.lz4" -mtime +2 -exec rm -f {} \;

echo "Moving snapshot and updating link in HTML..."
sudo mv -f $HOME/$SNAP_FILENAME $HTML_PATH/$SNAP_FILENAME
sudo sed -i.bak -e "s|Snapshot: <a href=\".*\">Download.*</a>|Snapshot: <a href=\"https://$DOMAIN_PREFIX.$DOMAIN/$SNAP_FILENAME\">Download</a>|" "$HTML_PATH/index.html"

# Cleanup temporary working directory
echo "Cleaning up temporary files..."
rm -rf "$WORK_DIR"

echo "Snapshot completed successfully!"
