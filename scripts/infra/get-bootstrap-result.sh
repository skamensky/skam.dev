DATA_DIR="/home/ubuntu/.skam-data/bootstrap"
BOOTSTRAP_SENTINEL="$DATA_DIR/bootstrap_exit_status.txt"
start_time=$SECONDS
while [ ! -f $BOOTSTRAP_SENTINEL ] ; do
  if [ $((SECONDS - start_time)) -gt 300 ]; then
    echo "Timed out waiting for bootstrap to complete" >&2
    exit 1
  fi
  sleep 1
done

result=`cat $BOOTSTRAP_SENTINEL`

if [ "$result" == "0" ]; then
  echo "Bootstrap succeeded"
  exit 0
else
  echo "Bootstrap failed" >&2
  echo "stderr"
  cat /home/ubuntu/.skam-data/bootstrap/setup_stderr.log
  cat $DATA_DIR/setup_stdout.log
  echo "stdout"
  cat $DATA_DIR/setup_stdout.log
  exit 1
fi