set -e

STAGE=$1
function build_and_exit() {
  /bin/rm -rf /mnt/frontend/dist
  /bin/cp -rf dist /mnt/frontend/
  exit 0
}

function watch_frontend(){
  cd /mnt/host/frontend
  yarn watch
}


if [ "$STAGE" = "prod" ]; then
  build_and_exit
else
  watch_frontend
fi
