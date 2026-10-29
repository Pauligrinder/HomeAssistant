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

# Chum OBS tree arch segment (i486 target uses i486 in the repo path).
CHUM_ARCH="$ARCH"
CHUM_REPO_URL="${CHUM_REPO_URL:-https://repo.sailfishos.org/obs/sailfishos:/chum/4.6_${CHUM_ARCH}/}"
CHUM_REPO_NAME="${CHUM_REPO_NAME:-sailfishos-chum}"

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
    -e CHUM_REPO_NAME="$CHUM_REPO_NAME" \
    -e CHUM_REPO_URL="$CHUM_REPO_URL" \
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
        # MapLibre comes from SailfishOS:Chum; vendor into the RPM at install time.
        if ! sb2 -t "${TARGET}" -R rpm -q mapboxgl-qml >/dev/null 2>&1; then
          echo "Adding SailfishOS:Chum and installing MapLibre build deps..."
          sb2 -t "${TARGET}" -m sdk-install -R ssu ar "${CHUM_REPO_NAME}" "${CHUM_REPO_URL}" || true
          sb2 -t "${TARGET}" -m sdk-install -R ssu ur || true
          sb2 -t "${TARGET}" -m sdk-install -R zypper --non-interactive ref || true
          sb2 -t "${TARGET}" -m sdk-install -R zypper --non-interactive in -y \
              mapboxgl-qml qmaplibregl qmaplibregl-devel
        fi
        sb2 -t "${TARGET}" -m sdk-install -R zypper --non-interactive in -y patchelf \
            >/dev/null 2>&1 || true
        # sdk-install above mutates the original target; mb2 default snapshot
        # reset needs sudo that CI images do not grant. Build on the target itself.
        mb2 --target "${TARGET}" --no-snapshot=force build
        if [ ! -f "RPMS/${RPM_NAME}" ]; then
            echo "Expected RPM not found: RPMS/${RPM_NAME}" >&2
            ls -la RPMS || true
            exit 1
        fi
        cp -v "RPMS/${RPM_NAME}" /out/
    '

echo "Artifacts:"
ls -la "$ROOT/RPMS"
