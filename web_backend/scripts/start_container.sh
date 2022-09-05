set -e

STAGE=$1
function watch(){
  cd /mnt/host/web_backend

  CompileDaemon -exclude="main" -pattern=".*" -command="./main" -build="go build -o main" -color="true"
}


if [ "$STAGE" = "prod" ]; then
  ./main
else
  watch
fi
