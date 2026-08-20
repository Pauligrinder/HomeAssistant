#!/bin/sh
# Build harbour-helmsman RPMs inside the Sailfish Platform SDK Docker image.
# Usage: scripts/ci-build.sh <arch> [version] [release]
# Example: scripts/ci-build.sh aarch64 0.1.9 1

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${1:?arch required (aarch64|armv7hl|i486)}"
PRO_FILE="$ROOT/app/harbour-homeassistant.pro"
SFOS_RELEASE="${SFOS_RELEASE:-5.2.0.15}"
IMAGE="${SDK_IMAGE:-coderus/sailfishos-platform-sdk:${SFOS_RELEASE}}"
TARGET="SailfishOS-${SFOS_RELEASE}-${ARCH}"

VERSION="${2:-}"
if [ -z "$VERSION" ]; then
    VERSION="$(sed -n 's/^VERSION *= *//p' "$PRO_FILE" | head -1 | tr -d '[:space:]')"
fi
RELEASE="${3:-1}"

if [ -z "$VERSION" ]; then
    echo "Could not determine VERSION" >&2
    exit 1
fi

echo "Building harbour-helmsman-${VERSION}-${RELEASE}.${ARCH}.rpm"
echo "  image=$IMAGE"
echo "  target=$TARGET"

docker pull "$IMAGE"

mkdir -p "$ROOT/RPMS"

# Copy the app tree into the container and build there (same idea as
# coderus/github-sfos-build) so host UID/permissions do not matter.
docker run --rm --privileged \
    -v "$ROOT/app:/app:ro" \
    -v "$ROOT/RPMS:/out" \
    -e VERSION="$VERSION" \
    -e RELEASE="$RELEASE" \
    -e TARGET="$TARGET" \
    "$IMAGE" \
    /bin/bash -lc '
        set -e
        mkdir -p /home/mersdk/build
        cp -a /app/. /home/mersdk/build/
        cd /home/mersdk/build
        sed -i \
            -e "s/^Version:.*/Version:    ${VERSION}/" \
            -e "s/^Release:.*/Release:    ${RELEASE}/" \
            rpm/harbour-homeassistant.spec
        mb2 --target "${TARGET}" build
        mkdir -p /out
        find RPMS -type f -name "*.rpm" ! -name "*-debuginfo-*" ! -name "*-debugsource-*" \
            -exec cp -v {} /out/ \;
        # Ensure the runner can read the artifacts.
        chmod -R a+rX /out || sudo chmod -R a+rX /out
    '

echo "Artifacts:"
ls -la "$ROOT/RPMS"
