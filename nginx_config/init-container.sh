#!/bin/bash

CERTBOT_DATA_DIR="/mnt/cert_data/certbot"

function init_volume() {
  mkdir -p /mnt/nginx_data/nginx/
  cp -rf /etc/nginx/* /mnt/nginx_data/nginx/
  mkdir -p /mnt/nginx_data/logs
}

function setup_ssl(){
  mkdir -p $CERTBOT_DATA_DIR
  WEB_DIR="$CERTBOT_DATA_DIR/live/skam.dev"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > $CERTBOT_DATA_DIR/conf/options-ssl-nginx.conf
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > $CERTBOT_DATA_DIR/conf/ssl-dhparams.pem
  if [ ! -f "$WEB_DIR/privkey.pem" ]; then
    # this is the first time we are running nginx. We need to create a dummy key.
    # idea taken from https://pentacent.medium.com/nginx-and-lets-encrypt-with-docker-in-less-than-5-minutes-b4b8a60d3a71
    # this key will be overwritten by the real key when certbot runs for the first time.
    openssl req -x509 -nodes -newkey rsa:4096 -days 1 \
        -keyout "$WEB_DIR/privkey.pem" \
        -out "$WEB_DIR/fullchain.pem" \
        -subj '/CN=localhost'
  fi
}

function env_specific_commands(){
  if [ "$STAGE" == "dev" ]
  then
    cp -rf /etc/nginx/nginx-dev.conf /etc/nginx/nginx.conf
  else
    setup_ssl
  fi
}
function init_nginx(){
  nginx
}

function nginx_reloader(){
# reload once a day to make sure we obtain newly created SSL certificates
  while true; do
    nginx -s reload
    sleep 24h
  done
}

env_specific_commands
init_volume
init_nginx
nginx_reloader