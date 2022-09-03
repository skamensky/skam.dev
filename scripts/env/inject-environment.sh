#!/usr/bin/env bash

# meant to be called at the beginning of any script interacting with docker-compose
# ensures STAGE is set
# exports all the docker environment variables to the current shell
# sets DOCKER_PROJECT_NAME
# cd's to the root of the project

export DOCKER_PROJECT_NAME='skam'

USAGE="Please set the environment variable \$STAGE to 'prod' or 'dev' , (no quotes, case does not matter)"


if [ -z "$STAGE" ]; then
      echo "Error: \$STAGE is empty. $USAGE" 1>&2
      exit 1
fi

ENV_DIR="scripts/env"

check_required_env () {
  REQUIRED_ENV='''
STAGE
POSTGRES_PORT
POSTGRES_HOST
DEBUG
REDIS_HOST
REDIS_PORT
'''
  # i learned about arrays here https://stackoverflow.com/questions/2013396/mutable-list-or-array-structure-in-bash-how-can-i-easily-append-to-it
  MISSING_ENV_VARS=()
  for env_var in $REQUIRED_ENV
  do
    # thanks to https://stackoverflow.com/a/16553351/4188138 for this line
    if [[ -z ${!env_var} ]]
    then
      MISSING_ENV_VARS+=("$env_var")
    else
      echo "Found value in environment for $env_var"
    fi
  done
  # from https://serverfault.com/a/477506/502550
  if [ ${#MISSING_ENV_VARS[@]} -eq 0 ]; then
    echo "All required environment variable exist"
  else
    echo "EXITING EARLY. MISSING REQUIRED ENVIRONMENT VARIABLES:"
    echo "${MISSING_ENV_VARS[@]}"
    exit 1
  fi

}


# convert to lower case
STAGE=`echo $STAGE | tr '[A-Z]' '[a-z]'`
if [[ "$STAGE" == "prod" ]]; then
    echo "stage is prod"
    export $(cat "$ENV_DIR/.prod.env" |grep -v '^#'| xargs)
    cp -rf "$ENV_DIR/.prod.env" "$ENV_DIR/.effective-env.env"
    echo "injected environment variables from $ENV_DIR/.prod.env"
    echo "copied environment to $ENV_DIR/.effective-env.env"
elif [ "$STAGE" == "dev" ]; then
    echo "stage is dev"
    export $(cat "$ENV_DIR/.dev.env" |grep -v '^#'| xargs)
    cp -rf "$ENV_DIR/.dev.env" "$ENV_DIR/.effective-env.env"
    echo "injected environment variables from $ENV_DIR/.dev.env"
    echo "copied environment to $ENV_DIR/.effective-env.env"
else
  echo "\$STAGE env is '$STAGE'. $USAGE" 1>&2
fi

if [[ -f "$ENV_DIR/secrets.env" ]]; then
    export $(cat "$ENV_DIR/secrets.env" | xargs)
    echo "" >> "$ENV_DIR/.effective-env.env"
    cat "$ENV_DIR/secrets.env" >> "$ENV_DIR/.effective-env.env"
else
    echo "EXITING EARLY. MISSING SECRETS FILE (it should be here $ENV_DIR/secrets.env)"
    exit 1
fi

check_required_env
