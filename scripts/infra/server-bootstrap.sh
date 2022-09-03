#!/bin/bash

set -e
set -x


DATA_DIR=/home/ubuntu/.skam-data/bootstrap
SETUP_SENTINEL="${DATA_DIR}/initial-server-setup-complete"
mkdir -p $DATA_DIR

# upload output to s3, see https://www.linuxjournal.com/content/bash-trap-command
function on_exit()
{
  # reraise the original exit status
  exit_status=$?
  printf $exit_status > "${DATA_DIR}/bootstrap_exit_status.txt"
  exit $exit_status
}

trap on_exit EXIT



set_docker_data_root(){
  # from https://stackoverflow.com/a/52537027/4188138

  # start for the first time to create all necessary files
  systemctl start docker || true
  # stop so we can move files around
  systemctl stop docker || true

  if [ -d "/mnt/data/docker_root" ]; then
    echo "WARNING: docker root already exists on mounted volume. Skipping overwrite and using data that already exists." >&2
    rm -rf /var/lib/docker
  else
    echo "moving docker root to live on the mounted EBS volume"
    mv /var/lib/docker /mnt/data/docker_root
  fi

  ln -s /mnt/data/docker_root /var/lib/docker

  systemctl start docker
}

create_skam_main_service(){
  rm -f /etc/systemd/system/skam.service
  cat > /etc/systemd/system/skam.service <<EOF
[Unit]
Description=Skam Main Web App
After=network.target
StartLimitIntervalSec=0

[Service]
Environment=STAGE=prod
Type=simple
Restart=always
RestartSec=1
User=root
WorkingDirectory=/home/ubuntu/skam.dev/
ExecStart=/usr/bin/bash scripts/docker/ops.sh up
ExecStop=/usr/bin/bash scripts/docker/ops.sh down

[Install]
WantedBy=multi-user.target
EOF
systemctl start skam
systemctl enable skam
}

wait_until_volume_attached(){
  # the infra script starts the instance and calls this script before it attaches the volume. We need to wait until that step is complete.
  echo "Waiting for volume to be attached"
  while true; do
    current_state=`aws ec2 describe-volumes --filters "Name=tag:Name,Values=skam-website"  --query "Volumes[0].Attachments[0].State" --output text --region eu-west-3`
    if [ "$current_state" == "attached" ]; then
      echo "Volume attached"
      break
    fi
    sleep 1
  done
}

mount_ebs(){
  # from https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-using-volumes.html
  # and
  # https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-using-volumes.html#ebs-mount-after-reboot

  xvdf=`lsblk |grep xvdf`
  if [[ "$xvdf" == */* ]]; then
    echo "WARNING File system already mounted. Skipping mount ebs function" >&2
    return
  fi

  mkdir -p /mnt/data
  has_file_system=`file -s /dev/xvdf`
  #taken from https://superuser.com/a/667100/490393
  mnt_contents=`find /mnt/data/ -mindepth 1 -maxdepth 1`

  if [[ "$has_file_system" != "/dev/xvdf: data" ]]; then
    echo "file -s /dev/xvdf produced non empty output. Filesystem already present on device. Skipping filesystem creation step." >&2
    else
        apt-get install xfsprogs
        # xfs supports storage quota's which can be useful for using in docker
        mkfs -o pquota -t xfs /dev/xvdf
 fi

  if [[ "$mnt_contents" != "" ]]; then
    echo "Critical failure: /mnt/data directory is not empty before mounting. Cannot mount. Exiting early" >&2
      exit 1
    else
      mount /dev/xvdf /mnt/data
  fi

  # remount file system on reboot
  cp /etc/fstab /etc/fstab.bak
  dev_uid=`blkid|grep /dev/xvdf|python3 -c "import sys;print(sys.stdin.read().split('\"')[1])"`
  echo "UUID=$dev_uid  /mnt/data  xfs  defaults,nofail  0  2" >> /etc/fstab

  # verify our fstab is valid
  umount /mnt/data && mount -a && touch "${DATA_DIR}/fstab-is-valid"
  if [[ ! -f "${DATA_DIR}/fstab-is-valid" ]]; then
      echo "Error with mount configuration. Restoring fstab from backup. Exiting early." >&2
      cp /etc/fstab /etc/fstab.corrupt
      cp /etc/fstab.bak /etc/fstab
      exit 1
    else
      echo "fstab is valid"
      rm -f /etc/fstab.corrupt
      rm /etc/fstab.bak
  fi

}

install_packages(){
  apt-get update
  apt-get -y install python3-pip python3-virtualenv snapd awscli
}

install_docker(){
  export VERSION=20.10.17
  curl -fsSL https://get.docker.com -o get-docker.sh
  # remove the unnecessary sleep
  cat get-docker.sh | grep -v "( set -x; sleep 20 )" > get-docker-no-sleep.sh

  sh get-docker-no-sleep.sh
  rm get-docker.sh get-docker-no-sleep.sh
  groupadd docker 2>/dev/null || true
  usermod -aG docker ubuntu
}

init_os(){

  echo "Executing install_docker"
  install_docker
  echo "install_docker finished running"

  echo "Executing install_packages"
  install_packages
  echo "install_packages finished running"

  echo "Executing attach_volume"
  wait_until_volume_attached
  echo "attach_volume finished running"

  echo "Executing mount_ebs"
  mount_ebs
  echo "mount_ebs finished running"

  echo "Executing set_docker_data_root"
  set_docker_data_root
  echo "set_docker_data_root finished running"

#  commenting this out since during deploy we mess with the same commands that the service does. We want the logs from the deploy scripts
#  and I didn't want to use the output of journalctl to the file since it's harder to find out when the deploy started and ended

# maybe we'll have a use for this just for starting the service upon reboot.

#  echo "Executing create_skam_main_service"
#  create_skam_main_service
#  echo "create_skam_main_service finished running"

  echo "All functions completed. Creating ${SETUP_SENTINEL}"
  touch "${SETUP_SENTINEL}"
  echo "Done setting up remote server"
}


# grouping commands to capture output as a single stream.
# see https://www.gnu.org/software/bash/manual/html_node/Command-Grouping.html
{
  set -x
  if [[ -f "${SETUP_SENTINEL}" ]]; then
    echo "Remote server already set up. Exiting without doing anything"
    exit 0
  else
    echo "This is the first time deploying to this server. Initiating server setup"
    init_os
  fi
} 1> "${DATA_DIR}/setup_stdout.log"  2>"${DATA_DIR}/setup_stderr.log"