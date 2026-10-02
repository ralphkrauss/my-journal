#!/bin/bash
# Exercise the shipped image with its default user and a persistent data volume.
set -euo pipefail
image="${1:?Usage: test-server-image.sh <image> <linux/amd64|linux/arm64>}"
platform="${2:?Specify the image platform}"
case "$platform" in linux/amd64 | linux/arm64) ;; *) exit 2 ;; esac
[[ "$(docker image inspect "$image" --format '{{.Os}}/{{.Architecture}}')" == "$platform" ]]
image_user="$(docker image inspect "$image" --format '{{.Config.User}}')"
case "$image_user" in '' | root | 0 | 0:* | root:*)
  echo 'The server image must declare a nonroot user.' >&2
  exit 1
  ;;
esac
container="journal-image-$$-$RANDOM"
volume="$container-data"
cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
  docker volume rm "$volume" >/dev/null 2>&1 || true
}
trap cleanup EXIT
docker volume create "$volume" >/dev/null
docker run -d --name "$container" --platform "$platform" --read-only \
  --cap-drop ALL --security-opt no-new-privileges:true \
  --tmpfs /tmp:rw,size=32m,mode=1777 -v "$volume:/data" "$image" >/dev/null
for cycle in 1 2; do
  ready=false
  for _ in {1..50}; do
    if docker exec "$container" dotnet Journal.Api.dll --health-check >/dev/null 2>&1; then
      ready=true
      break
    fi
    [[ "$(docker inspect "$container" --format '{{.State.Running}}')" == true ]] || break
    sleep 0.2
  done
  if [[ "$ready" != true ]]; then
    docker logs "$container"
    echo 'Server image failed its health check.' >&2
    exit 1
  fi
  docker stop "$container" >/dev/null
  [[ "$(docker inspect "$container" --format '{{.State.ExitCode}}')" == 0 ]] || {
    docker logs "$container"
    echo 'Server image did not shut down cleanly.' >&2
    exit 1
  }
  if [[ "$cycle" == 1 ]]; then docker start "$container" >/dev/null; fi
done
echo 'PASS: matching image architecture, default nonroot user, read-only root, persistent-volume restart and clean shutdown'
