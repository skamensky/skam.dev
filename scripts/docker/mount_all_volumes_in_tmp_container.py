#! /usr/bin/python3

# TODO, migrate this to a go script

import os
import subprocess
from logging import basicConfig,getLogger
basicConfig(level='INFO')
logger = getLogger()

list_command  = ["docker","volume","ls",'--format={{.Name}}' ]
logger.info(f"running command: {' '.join(list_command)}")
list_result=subprocess.run(list_command, capture_output=True)
if list_result.stderr:
    raise Exception(f"Error listing volumes: {list_result.stderr.decode()}")
docker_volumes = subprocess.run(list_command,capture_output=True).stdout.decode().splitlines()
logger.info(f"Attempting to mount {len(docker_volumes)} volumes into a temporary container...")

volumes_as_mounts = []
for vol_name in docker_volumes:
    if vol_name.startswith('skam_'):

        volumes_as_mounts.append(f"-v {vol_name}:/mnt/skam/{vol_name.replace('skam_','')}")
    else:
        volumes_as_mounts.append(f"-v {vol_name}:/mnt/{vol_name}")

temp_container_command = f'docker run  -w /mnt/skam -it {" ".join(volumes_as_mounts)} python:3.9.6-bullseye bash'
os.system(temp_container_command)
# todo add the command
#du -sh *|sort -h && echo "Total: `du -sh`"
# to the image automatically
