set -e

STAGE=$1
function watch(){
  cd /mnt/host/web_backend
  CompileDaemon -pattern=".*" -command="./main" -build="go build -o main" -color="true"
}


if [ "$STAGE" = "prod" ]; then
  build_and_exit
else
  watch
fi
