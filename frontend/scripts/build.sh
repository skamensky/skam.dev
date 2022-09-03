set -e

STAGE=$1

if [ "$STAGE" = "prod" ]; then
  yarn build:prod
else
  yarn build:dev
fi
