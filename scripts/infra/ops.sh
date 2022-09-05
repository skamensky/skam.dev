set -e
# TODO validate that we're running from the root

SSH_KEY_PATH=~/.ssh/skam_website
USAGE="usage: ./scripts/infra/ops.sh [init|create|destroy|recreate|print-login] [--remove-volume]"
if [ $# -eq 0 ]; then
    echo "$USAGE"
    exit 1
fi

REMOVE_VOLUME="false"
if [ $# -eq 2 ]; then
    if [ "$2" == "--remove-volume" ]; then
        REMOVE_VOLUME="true"
    else
        echo "$USAGE"
        exit 1
    fi
fi

function wait_until_bootstrap_complete(){
    # cat the file from the remote server via ssh

    ssh_login="null"
    echo "Attempting to connect via ssh..."

    ssh_login_command=`print_ssh_login`
    # wait until connection succeeds
    while [ "$ssh_login" == "null" ]; do
        ssh_login=`$ssh_login_command  echo "connected" 2>/dev/null||echo "null"`
    done

    echo "Connected via ssh. Waiting for bootstrap to complete..."
    $ssh_login_command "bash -s" < scripts/infra/get-bootstrap-result.sh
}

function get_ip_address(){
  ip_address=`terraform -chdir="scripts/infra/terraform" show -json |jq -r ".values.root_module.resources[].values.public_ip" 2>/dev/null|grep -v "null"||echo "null"`
  echo "$ip_address"
}

function wait_until_ip_available(){
  ip_address="null"
  max_seconds=180
  # from https://www.xmodulo.com/measure-elapsed-time-bash.htm
  start_time=$SECONDS

  while [ "$ip_address" == "null" ]; do
    ip_address=`get_ip_address`
    if [ $((SECONDS - start_time)) -gt $max_seconds ]; then
      echo "Timed out waiting for IP address" >&2
      echo "null"
      break
    fi
    sleep 1
  done
  echo "$ip_address"
}

function write_new_ip_to_prod_env(){
  ip_address=`wait_until_ip_available`
  if [ "$ip_address" == "null" ]; then
    echo "Could not write new IP address to scripts/env/.prod.env" >&2
  else
      sed -i "s/SSH_IP=.*/SSH_IP=$ip_address/g" scripts/env/.prod.env
      echo "Wrote new IP address to scripts/env/.prod.env"
  fi
}

function print_ssh_login() {
  ip_address=`wait_until_ip_available`
  if [ "$ip_address" == "null" ]; then
    echo "null"
    echo "Could not retrieve ip address. Server may still be instantiating" >&2
    else
      echo "ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no -i $SSH_KEY_PATH ubuntu@$ip_address"
  fi
}

function create_ssh_key_if_not_exist() {
    if [ ! -f ~/.ssh/skam_website ]; then
      mkdir -p ~/.ssh
      echo "ssh key does not exist, creating it"
      ssh-keygen -t rsa -b 4096 -N "" -f $SSH_KEY_PATH 2>/dev/null 1>/dev/null
      chmod 400 ~/.ssh/skam_website
    fi
}

function create(){
  create_ssh_key_if_not_exist
  terraform -chdir="scripts/infra/terraform" apply -var="ssh_public_key_file_path=${SSH_KEY_PATH}.pub" -auto-approve
  echo "Terraform command complete. Waiting for bootstrap to finish."
  wait_until_bootstrap_complete
  echo "Login with the following command:"
  print_ssh_login
  write_new_ip_to_prod_env
}

function destroy(){

  read -p "Are you sure you want to destroy the infrastructure? (y/n) " -n 1 -r
  echo

  if [[ ! $REPLY =~ ^[Yy]$ ]];  then
      echo "Aborting"
      exit 1
  fi


  if [ $REMOVE_VOLUME == "false" ]; then
    volume_id=`terraform -chdir="scripts/infra/terraform" show -json | jq -r ".values.root_module.resources[].values.id" 2>/dev/null|grep "vol-" ||echo "null"`

    if [[ ! "$volume_id" == vol-* ]]; then
      echo "Could not find volume. Manual intervention required."
      exit 1
    fi
    echo "Temporarily removing volume with id $volume_id from terraform state"
    echo "In case of script failure, run the following command to reattach it to the state manually"
    echo "terraform -chdir=\"scripts/infra/terraform\"  import  -var=\"ssh_public_key_file_path=${SSH_KEY_PATH}.pub\" aws_ebs_volume.volume \"$volume_id\""
    # removing temporarily since we never want to delete the volume. See https://stackoverflow.com/a/55271805/4188138
    terraform -chdir="scripts/infra/terraform" state rm aws_ebs_volume.volume
  else
    echo "You have chosen to remove the volume. Goodbye data."
  fi

  terraform -chdir="scripts/infra/terraform" destroy -var="ssh_public_key_file_path=${SSH_KEY_PATH}.pub" -auto-approve

  if [ $REMOVE_VOLUME == "false" ]; then
    echo "Re-adding volume with id $volume_id to terraform state"
    terraform -chdir="scripts/infra/terraform"  import  -var="ssh_public_key_file_path=${SSH_KEY_PATH}.pub" aws_ebs_volume.volume "$volume_id"
  fi

  echo "Deletion complete"
}

function init(){
  # creates the s3 bucket for terraform
  terraform -chdir="scripts/infra/terraform/terraform_init" init
  terraform -chdir="scripts/infra/terraform/terraform_init" apply -auto-approve
  # handles the actual resource deployment
  terraform -chdir="scripts/infra/terraform" init
}

case "$1" in
  init)
    init
    ;;

  create)
    create
    ;;

  destroy)
    destroy
    ;;

  recreate)
    destroy
    create
    ;;

  print-login)
    print_ssh_login
    ;;

  *)
    echo "$USAGE"
    exit 1
    ;;
esac
