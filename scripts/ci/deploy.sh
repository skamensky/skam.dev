#!/usr/bin/env bash
# TODO make sure we're running in the root of the repo

set -e
set -x
export STAGE=prod
source ./scripts/env/inject-environment.sh

export root_project_dir="$(pwd)"
trap "cd \"$root_project_dir\"" EXIT


rm -rf /tmp/deploy-skam-over-ssh
mkdir /tmp/deploy-skam-over-ssh
cd /tmp/deploy-skam-over-ssh
git clone https://github.com/skamensky/skam.dev --depth 1
cd skam.dev
cp "$root_project_dir/scripts/env/secrets.env" ./scripts/env/secrets.env


ssh_key_full_path="$HOME/$SSH_KEY_LOCATION_FROM_HOME"
# replace these lines with your ssh credentials. Make sure docker and docker-compose are installed on the remote server
rsync -Pav --exclude='.git/' --delete --delete-excluded -e "ssh -i $ssh_key_full_path" . ubuntu@$SSH_IP:/home/ubuntu/skam.dev
ssh -i $ssh_key_full_path ubuntu@$SSH_IP -t "STAGE=prod cd skam.dev && /bin/bash ./scripts/docker/ops.sh up"

cd $root_project_dir