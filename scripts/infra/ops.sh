set -e

# TODO validate that we're running from the root

SSH_KEY_PATH=~/.ssh/skam_website
USAGE="usage: ./scripts/infra/ops.sh [init|create|destroy|recreate|print-login]"
if [ $# -eq 0 ]; then
    echo "$USAGE"
    exit 1
fi

if  [ "$1" != "init" ] && [ "$1" != "create" ] && [ "$1" != "destroy" ] && [ "$1" != "recreate" ] && [ "$1" != "print-login" ]; then
    echo "$USAGE"
    exit 1
fi

function print_login_info() {
  ip_address=`terraform -chdir="scripts/infra/terraform" show -json |jq -r ".values.root_module.resources[].values.public_ip" 2>/dev/null|grep -v "null"||echo "null"`
  if [ "$ip_address" == "null" ]; then
    echo "Could not retrieve ip address. Server may still be instantiating"
    else
      echo "ssh -o StrictHostKeyChecking=no -i $SSH_KEY_PATH ubuntu@$ip_address"
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
  echo "Creation complete. Retrieving login information"
  print_login_info
}

function destroy(){

  # confirm yes or no
  read -p "Are you sure you want to destroy the infrastructure? (y/n) " -n 1 -r
  echo

  if [[ ! $REPLY =~ ^[Yy]$ ]];  then
      echo "Aborting"
      exit 1
  fi

  volume_id=`terraform -chdir="scripts/infra/terraform" show -json | jq -r ".values.root_module.resources[].values.id"|grep "vol-"`
   if [ "$volume_id" == "" ]; then
     echo "Could not find volume. Manual intervention required."
     exit 1
   fi

  echo "Temporarily removing volume with id $volume_id from terraform state"
  echo "In case of script failure, run the following command to reattach it to the state manually"
  echo "terraform -chdir=\"scripts/infra/terraform\"  import  -var=\"ssh_public_key_file_path=${SSH_KEY_PATH}.pub\" aws_ebs_volume.volume \"$volume_id\""
  # removing temporarily since we never want to delete the volume. See https://stackoverflow.com/a/55271805/4188138
  terraform -chdir="scripts/infra/terraform" state rm aws_ebs_volume.volume
  terraform -chdir="scripts/infra/terraform" destroy -var="ssh_public_key_file_path=${SSH_KEY_PATH}.pub" -auto-approve
  terraform -chdir="scripts/infra/terraform"  import  -var="ssh_public_key_file_path=${SSH_KEY_PATH}.pub" aws_ebs_volume.volume "$volume_id"
  echo "Deletion complete"
}

function init(){
  # creates the s3 bucket for terraform
  terraform -chdir="scripts/infra/terraform/terraform_init" init
  terraform -chdir="scripts/infra/terraform/terraform_init" apply -auto-approve
  # handles the actual resource deployment
  terraform -chdir="scripts/infra/terraform" init
}

if [ "$1" == "init" ]; then
  init
fi

if [ "$1" == "create" ]; then
  create
fi

if [ "$1" == "destroy" ]; then
    destroy
fi

if [ "$1" == "recreate" ]; then
    destroy
    create
fi

if [ "$1" == "print-login" ]; then
  print_login_info
fi