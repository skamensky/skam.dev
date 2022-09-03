#!/bin/bash
set -e
set -x

if [ "$STAGE" == "dev" ]; then
  echo "Currently in dev mode. No need to run certbot. Exiting the container"
  exit 0
fi

export CERTBOT_DATA_DIR="/mnt/cert_data/certbot"
export INIT_SENTINEL_FILE="$CERTBOT_DATA_DIR/initial-setup-complete.sentinel"



function first_time_challenges(){

  mkdir -p /mnt/cert_data/logs
  # TODO, update or delete this comment. Do we actually need to delete the certificates manually?
  # the workflow is that nginx creates dummy certs. Make sure those are deleted.
  rm -rf /mnt/cert_data/certbot/live/skam.dev
  certbot \
    certonly  \
    --webroot \
    --agree-tos \
    --no-eff-email \
    --webroot-path=/mnt/cert_data/certbot/conf/ \
    --email shmuelkamensky@gmail.com \
    --domains skam.dev,www.skam.dev,shmuelkamensky.com,www.shmuelkamensky.com \
    --config-dir $CERTBOT_DATA_DIR \
    --logs-dir /mnt/cert_data/logs \
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

renew_every_12_hours
