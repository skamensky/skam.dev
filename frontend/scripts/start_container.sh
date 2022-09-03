set -e

STAGE=$1
function copy_build_to_shared_volume() {
  /bin/rm -rf /mnt/frontend/dist
  /bin/cp -rf dist /mnt/frontend/
  exit 0
}

function watch_frontend(){
  cd /mnt/host/frontend
  yarn watch
}


if [ "$STAGE" = "prod" ]; then
  copy_build_to_shared_volume
else
  watch_frontend
fi
