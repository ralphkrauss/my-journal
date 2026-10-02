#!/bin/bash
# Validate a Linux package with native OS dependencies but no installed .NET runtime.
set -euo pipefail
package="${1:?Usage: test-packaged-container.sh <server-package-directory> <linux/amd64|linux/arm64>}"
platform="${2:?Specify the package platform}"
case "$platform" in
  linux/amd64 | linux/arm64) ;;
  *)
    echo "Unsupported platform." >&2
    exit 2
    ;;
esac
package="$(cd "$package" && pwd)"
container="journal-package-$$-$RANDOM"
created=false
trap 'if [[ "$created" == true ]]; then docker rm -f "$container" >/dev/null 2>&1 || true; fi' EXIT
docker run -d --name "$container" --platform "$platform" --read-only --user 1654:1654 \
  --tmpfs /tmp:rw,mode=1777 --tmpfs /data:rw,mode=700,uid=1654,gid=1654 \
  -e Journal__DataDirectory=/data -e ASPNETCORE_URLS=http://+:8080 \
  -e DOTNET_BUNDLE_EXTRACT_BASE_DIR=/tmp/bundle -v "$package:/app:ro" \
  mcr.microsoft.com/dotnet/runtime-deps:10.0.12 /app/Journal.Api >/dev/null
created=true
ready=false
for _ in {1..50}; do
  if docker exec "$container" /app/Journal.Api --health-check; then
    ready=true
    break
  fi
  [[ "$(docker inspect "$container" --format '{{.State.Running}}')" == true ]] || break
  sleep 0.2
done
if [[ "$ready" != true ]]; then
  docker logs "$container"
  echo "Packaged server did not become healthy." >&2
  exit 1
fi
docker stop "$container" >/dev/null
[[ "$(docker inspect "$container" --format '{{.State.ExitCode}}')" == 0 ]] || {
  docker logs "$container"
  echo "Packaged server did not shut down cleanly." >&2
  exit 1
}
echo 'PASS: packaged Linux server is healthy as nonroot on a read-only filesystem without an installed .NET runtime; graceful shutdown succeeded'
