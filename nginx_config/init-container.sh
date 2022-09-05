#!/bin/bash

CERTBOT_DATA_DIR="/mnt/cert_data/certbot"

function wait_for_certbot_to_be_ready(){
  echo "Waiting for certbot to be ready"
  while [ ! -f /mnt/cert_data/status_for_nginx ]; do
    # todo add timeout
    sleep 1
  done
  result=$(cat /mnt/cert_data/status_for_nginx)
  if [ "$result" != "OK" ]; then
    echo "Certbot failed with message: $result. Exiting nginx early."
    exit 1
  else
    echo "Certbot sent \"OK\" to nginx. Starting nginx"
  fi

}

function init_volume() {
  mkdir -p /mnt/nginx_data/nginx/
  cp -rf /etc/nginx/* /mnt/nginx_data/nginx/
  mkdir -p /mnt/nginx_data/logs
}

function setup_ssl(){
  mkdir -p $CERTBOT_DATA_DIR
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > $CERTBOT_DATA_DIR/conf/options-ssl-nginx.conf
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > $CERTBOT_DATA_DIR/conf/ssl-dhparams.pem

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

wait_for_certbot_to_be_ready
env_specific_commands
init_volume
init_nginx
nginx_reloader