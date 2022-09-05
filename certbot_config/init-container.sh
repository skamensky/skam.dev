#!/bin/bash
set -e
set -x

# unfortunately, docker compose 3 syntax stopped supporting conditional startup order. See
# https://docs.docker.com/compose/startup-order/ and https://github.com/docker/compose/issues/4305
# therefore we need to communicate directly between the images
function signal_nginx_exit_status(){
  if [ "$?" -eq 0 ]; then
    status="OK"
  else
    status="ERROR, certbot exited with status $?"
  fi
  echo "$status" > /mnt/cert_data/status_for_nginx
}
trap signal_nginx_exit_status EXIT

if [ "$STAGE" == "dev" ]; then
  echo "Currently in dev mode. No need to run certbot. Exiting the container"
  exit 0
fi

export CERTBOT_DATA_DIR="/mnt/cert_data/certbot"
export INIT_SENTINEL_FILE="$CERTBOT_DATA_DIR/initial-setup-complete.sentinel"

# TODO add ,shmuelkamensky.com,www.shmuelkamensky.com
DOMAINS="skam.dev,www.skam.dev"

EMAIL="shmuelkamensky@gmail.com"
function first_time_challenges(){
  mkdir -p /mnt/cert_data/logs

  rm -rf /mnt/cert_data/certbot/live/skam.dev
  mkdir -p /mnt/cert_data/certbot/conf/
  certbot certonly \
    --standalone \
    --non-interactive \
    --agree-tos \
    --email $EMAIL \
    --no-eff-email \
    --domains $DOMAINS \
    --preferred-challenges http-01 \
    --http-01-port 80 \
    --logs-dir /mnt/cert_data/logs \
    --config-dir $CERTBOT_DATA_DIR \
    --webroot-path="$CERTBOT_DATA_DIR/conf" \
    --key-path "$CERTBOT_DATA_DIR/conf/skam.dev/privkey.pem" \
    --fullchain-path "$CERTBOT_DATA_DIR/conf/skam.dev/fullchain.pem" \
    && touch $INIT_SENTINEL_FILE
}

function renew_every_12_hours(){
  while true
  do
      echo "Renewing cert"
      certbot renew --config-dir "$CERTBOT_DATA_DIR"
      sleep 12h
  done
}
if [ ! -f "$INIT_SENTINEL_FILE" ]; then
  echo "Cert never created. Initializing first time first_time_challenges"
  first_time_challenges
  echo "first_time_challenges complete"
else
  echo "first_time_challenges has run in the past. Skipping first time challenges."
fi

# if we got here, nginx can start
echo "OK" > /mnt/cert_data/status_for_nginx
renew_every_12_hours
