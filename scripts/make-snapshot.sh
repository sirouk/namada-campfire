#!/usr/bin/env bash

# Variables
DOMAIN_PREFIX="namada"
HTML_PATH="/usr/share/nginx/html"
DOMAIN=$(grep -oP "(?<=href=\"https://$DOMAIN_PREFIX.).*?(?=/)" "$HTML_PATH/index.html" | head -1)
export CAMPFIRE_CHAIN_DATA="$HOME/chaindata/namada-2"
export CHAINDATA_PATH=${CHAINDATA_PATH:-$CAMPFIRE_CHAIN_DATA}
export FOUND_CHAIN_ID=$(awk -F'=' '/default_chain_id/ {gsub(/[ "]/, "", $2); print $2}' "$CHAINDATA_PATH/global-config.toml")
export CHAIN_ID=${CHAIN_ID:-$FOUND_CHAIN_ID}
SNAP_TIME=$(date -u +"%Y-%m-%dT%H.%M")
SNAP_FILENAME="${CHAIN_ID}_${SNAP_TIME}.tar.lz4"
TEMP_DIR="$HOME/temp_snapshot"

# Step 1: Sync Live Data to Temporary Directory
echo "Syncing live data to temporary directory..."
mkdir -p "$TEMP_DIR"
mkdir -p "$TEMP_DIR/db"
mkdir -p "$TEMP_DIR/cometbft/data"
rsync -av --delete "$CHAINDATA_PATH/$CHAIN_ID/db/" "$TEMP_DIR/db/"
rsync -av --delete "$CHAINDATA_PATH/$CHAIN_ID/cometbft/data/" "$TEMP_DIR/cometbft/data/"

# Step 2: Wait 30 seconds
echo "Waiting 30 seconds to ensure files have stabilized..."
sleep 30

# Step 3: Fix Only Incomplete Files in Temporary Directory
echo "Fixing incomplete files in the temporary directory..."
rsync -av --existing --inplace "$CHAINDATA_PATH/$CHAIN_ID/db/" "$TEMP_DIR/db/"
rsync -av --existing --inplace "$CHAINDATA_PATH/$CHAIN_ID/cometbft/data/" "$TEMP_DIR/cometbft/data/"

# Step 4: Create Snapshot from Temporary Directory
echo "Creating snapshot..."
sudo tar -C "$TEMP_DIR" -cf - db cometbft/data | lz4 - "$HOME/$SNAP_FILENAME"

# Step 5: Update Snapshot Location
echo "Moving snapshot to web directory..."
sudo rm -f "$HTML_PATH/*.tar.lz4"
sudo mv -f "$HOME/$SNAP_FILENAME" "$HTML_PATH/$SNAP_FILENAME"

# Step 6: Update HTML Index
echo "Updating snapshot link in HTML..."
sudo sed -i.bak -e "s|Snapshot: <a href=\".*\">Download</a>|Snapshot: <a href=\"https://$DOMAIN_PREFIX.$DOMAIN/$SNAP_FILENAME\">Download</a>|" "$HTML_PATH/index.html"

# Step 7: Cleanup Temporary Directory
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

echo "Snapshot completed successfully!"
