#!/usr/bin/env bash

# dependencies
apt-get install -y jq

### Grab the repo
rm -rf $HOME/namada-supply
cd $HOME
git clone -b main https://github.com/heliaxdev/namada-supply

# get the docker host ip
export TENDERMINT_URL=${TENDERMINT_URL:-"http://172.17.0.1:26657"}
export BUILD_ONLY=${BUILD_ONLY:-false}
export WIPE_VOLUMES=${WIPE_VOLUMES:-false}


# Load Campfire vars in environment
source $HOME/*.env

# check if the TLD_NAME is set
if [ -z "$DOMAIN" ]; then
  echo "DOMAIN is not set"
  exit 1
fi
export TLD_NAME=${DOMAIN}


# use jq to update the docker-compose.yml file for the environment.TENDERMINT_URL
# replace the TENDERMINT_URL in the docker-compose.yml file with the value of TENDERMINT_URL    
sed -i "s|TENDERMINT_URL=.*|TENDERMINT_URL=$TENDERMINT_URL|" $HOME/namada-supply/docker-compose.yml


# Build
cd $HOME/namada-supply


# Skip teardown and start if BUILD_ONLY is true
if [ "$BUILD_ONLY" = false ]; then
  # tear down
  cd $HOME/namada-supply
  
  # if there is any container containing the string "namada-supply-app" running, stop it
  DOCKER_RUNNING=$(docker ps -q -f name=namada-supply-app)
  if [ -n "$DOCKER_RUNNING" ]; then
      docker stop $DOCKER_RUNNING
      docker container rm --force $DOCKER_RUNNING
  fi

  if [ "$WIPE_VOLUMES" = true ]; then
      docker compose -f $HOME/namada-supply/docker-compose.yml down --volumes    
  else
      docker compose -f $HOME/namada-supply/docker-compose.yml down
  fi

  echo "Removing namada-supply-app images"
  docker image rm --force $(docker image ls --all | grep -E '^namada\/.*supply.*$' | awk '{print $3}') 2>/dev/null || true
  docker image rm --force $(docker image ls --all | grep '<none>' | awk '{print $3}') 2>/dev/null || true

  # prune all volumes (db data)
  if [ "$WIPE_VOLUMES" = true ]; then
      docker volume prune -fa
  fi
fi


# Build only or build and start
if [ "$BUILD_ONLY" = true ]; then
  # Just build
  docker compose -f $HOME/namada-supply/docker-compose.yml build
  echo "Build completed. Run the following command when ready to launch:"
  echo "docker compose -f $HOME/namada-supply/docker-compose.yml up -d"
else
  # Build and start the containers
  docker compose -f $HOME/namada-supply/docker-compose.yml up -d
fi

# --------------------------------------------------------------------
# TLS: ensure Certbot is installed and issue/renew the certificate
# --------------------------------------------------------------------

CERT_DOMAIN="supply.${TLD_NAME}"
CERT_PATH="/etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem"

# 1. Install certbot only if it is missing
if ! command -v certbot >/dev/null 2>&1; then
  echo "Certbot not found – installing certbot and nginx plugin..."
  apt-get update -y
  apt-get install -y certbot python3-certbot-nginx
fi

# 2. Obtain the certificate only if it does not already exist
if [ ! -f "$CERT_PATH" ]; then
  echo "Obtaining TLS certificate for ${CERT_DOMAIN}..."
  certbot --non-interactive --nginx \
          --register-unsafely-without-email --agree-tos \
          -d "${CERT_DOMAIN}"
else
  echo "TLS certificate for ${CERT_DOMAIN} already exists – skipping issuance."
fi