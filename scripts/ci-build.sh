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

RPM_NAME="harbour-helmsman-${VERSION}-${RELEASE}.${ARCH}.rpm"

echo "Building ${RPM_NAME}"
echo "  image=$IMAGE"
echo "  target=$TARGET"

docker pull "$IMAGE"

mkdir -p "$ROOT/RPMS"
# Bind mounts keep host ownership. Open the directory so the SDK user
# (mersdk) can write artifacts on GitHub Actions runners.
chmod a+rwx "$ROOT/RPMS"

# Copy the app tree into the container and build there (same idea as
# coderus/github-sfos-build) so host UID/permissions do not matter.
docker run --rm --privileged \
    -v "$ROOT/app:/app:ro" \
    -v "$ROOT/RPMS:/out" \
    -e VERSION="$VERSION" \
    -e RELEASE="$RELEASE" \
    -e ARCH="$ARCH" \
    -e TARGET="$TARGET" \
    -e RPM_NAME="$RPM_NAME" \
    "$IMAGE" \
    /bin/bash -lc '
        set -e
        mkdir -p /home/mersdk/build
        cp -a /app/. /home/mersdk/build/
        # Do not carry host app/RPMS into the build tree.
        rm -rf /home/mersdk/build/RPMS
        cd /home/mersdk/build
        sed -i \
            -e "s/^Version:.*/Version:    ${VERSION}/" \
            -e "s/^Release:.*/Release:    ${RELEASE}/" \
            rpm/harbour-homeassistant.spec
        mb2 --target "${TARGET}" build
        if [ ! -f "RPMS/${RPM_NAME}" ]; then
            echo "Expected RPM not found: RPMS/${RPM_NAME}" >&2
            ls -la RPMS || true
            exit 1
        fi
        cp -v "RPMS/${RPM_NAME}" /out/
    '

echo "Artifacts:"
ls -la "$ROOT/RPMS"
