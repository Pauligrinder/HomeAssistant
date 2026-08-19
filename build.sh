#!/bin/sh
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
CONTAINER="${CONTAINER:-helmsman-build}"
TARGET="${TARGET:-SailfishOS-5.2.0.15-aarch64}"
VERSION="${VERSION:-0.1.3}"

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "Creating SDK container $CONTAINER from coderus/sailfishos-platform-sdk-aarch64"
    docker create --name "$CONTAINER" coderus/sailfishos-platform-sdk-aarch64 sleep infinity
fi

docker start "$CONTAINER" >/dev/null

docker exec "$CONTAINER" sudo rm -rf /home/mersdk/app || true
docker cp "$ROOT/app" "$CONTAINER":/home/mersdk/app
docker exec -u root "$CONTAINER" chown -R mersdk:mersdk /home/mersdk/app
docker exec -w /home/mersdk/app "$CONTAINER" \
    mb2 --target "$TARGET" build

mkdir -p "$ROOT/app/RPMS"
docker cp "$CONTAINER":/home/mersdk/app/RPMS/harbour-helmsman-${VERSION}-1.aarch64.rpm \
    "$ROOT/app/RPMS/"
echo "Built $ROOT/app/RPMS/harbour-helmsman-${VERSION}-1.aarch64.rpm"
