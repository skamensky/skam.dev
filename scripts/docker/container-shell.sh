#!/usr/bin/env bash
set -e

source "scripts/env/inject-environment.sh"

CONTAINER_NAME=$1

if [ -z "$CONTAINER_NAME" ]; then
  echo "Usage: $0 <container name> (no compose prefix needed)"
  exit 1
fi

image_name_variations=("skam_docker_dns_${CONTAINER_NAME}" "skam_${CONTAINER_NAME}" "skam_${CONTAINER_NAME}_build" "${CONTAINER_NAME}")

for image_name in "${image_name_variations[@]}" ; do
  container_id=`docker container ls --filter "ancestor=${image_name}" -q`
  if [ -n "$container_id" ]; then
    docker exec -it "${container_id}" /bin/sh
    exit 0
  fi
done

echo "No container found with name ${CONTAINER_NAME}"
exit 1

