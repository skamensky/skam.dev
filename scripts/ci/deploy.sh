#!/usr/bin/env bash
# TODO make sure we're running in the root of the repo

set -e
set -x
export STAGE=prod
source ./scripts/env/inject-environment.sh

export root_project_dir="$(pwd)"
trap "cd \"$root_project_dir\"" EXIT


# useful when dev work required deployment and we don't want
if [ "$1" == "--from-local" ]; then
  echo "deploying from local"
else
  rm -rf /tmp/deploy-skam-over-ssh
  mkdir /tmp/deploy-skam-over-ssh
  cd /tmp/deploy-skam-over-ssh
  git clone https://github.com/skamensky/skam.dev --depth 1
  cd skam.dev
  cp "$root_project_dir/scripts/env/secrets.env" ./scripts/env/secrets.env
fi


ssh_key_full_path="$HOME/$SSH_KEY_LOCATION_FROM_HOME"
# thanks to https://stackoverflow.com/a/15373763/4188138 from the ":- .gitignore" trick
rsync -Pav --filter=':- .gitignore' --exclude='.git/' --delete --delete-excluded -e "ssh -i $ssh_key_full_path" . ubuntu@$SSH_IP:/home/ubuntu/skam.dev
# copy the secrets file over
scp -i "$ssh_key_full_path" "scripts/env/secrets.env" ubuntu@$SSH_IP:/home/ubuntu/skam.dev/scripts/env/secrets.env
ssh -i $ssh_key_full_path ubuntu@$SSH_IP -t "export STAGE=prod; cd skam.dev && /bin/bash ./scripts/docker/ops.sh up"