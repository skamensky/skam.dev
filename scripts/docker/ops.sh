#!/usr/bin/env bash

# TODO remove script_dir everwhere, make a script that ensures we are running from root of repo. If not, fail
# TODO write script to deploy start ec2 image, and attach volume
set -e
source "scripts/env/inject-environment.sh"

# for copy and paste purposes:
#export DOCKER_PROJECT_NAME='skam'

USAGE="usage: ./scripts/docker/ops.sh [up|down]"
COMMAND=$1
ENV_DIR="scripts/env"
if [ $# -eq 0 ]; then
    echo "$USAGE"
    exit 1
fi

if  [ "$COMMAND" != "up" ] && [ "$COMMAND" != "down" ]; then
    echo "$USAGE"
    exit 1
fi

# see https://stackoverflow.com/a/69519102/4188138
export COMPOSE_COMPATIBILITY=true

if [[ "$STAGE" == "prod" ]]; then
   DOCKER_COMPOSE_FILE="docker-compose-prod.yaml"
   else
    DOCKER_COMPOSE_FILE="docker-compose-dev.yaml"
fi

function up(){
  docker compose --project-name "$DOCKER_PROJECT_NAME" --file $DOCKER_COMPOSE_FILE down
  docker compose --project-name "$DOCKER_PROJECT_NAME" --file $DOCKER_COMPOSE_FILE build
  start_up_command="docker compose --project-name ${DOCKER_PROJECT_NAME} --env-file ${ENV_DIR}/.effective-env.env --profile ${STAGE} --file ${DOCKER_COMPOSE_FILE}  up  --remove-orphans"

  if [[ "$STAGE" == "prod" ]]; then
     start_up_command="${start_up_command} --detach && docker system prune --force"
  fi

  echo "Running the following docker command in order to start up"
  echo $start_up_command
  eval $start_up_command
}

function down(){
  set -x
  docker compose --project-name $DOCKER_PROJECT_NAME --file $DOCKER_COMPOSE_FILE down
  set +x
}

if [ "$COMMAND" == "up" ]; then
  up
elif [ "$COMMAND" == "down" ]; then
  down
fi
fi