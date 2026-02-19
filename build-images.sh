#!/bin/bash
#
# Lochs Image Builder
# Creates minimal FreeBSD images for the lochs-images registry
#
# Usage: ./build-images.sh [version]
# Example: ./build-images.sh 15.0
#

set -e

VERSION="${1:-15.0}"
RELEASE="${VERSION}-RELEASE"
ARCH="amd64"
BASE_URL="https://download.freebsd.org/releases/${ARCH}/${ARCH}/${RELEASE}"

WORK_DIR="$(pwd)/build"
OUTPUT_DIR="$(pwd)/output"

echo "=============================================="
echo "  Lochs Image Builder"
echo "  Building FreeBSD ${VERSION} images"
echo "=============================================="

# Create directories
mkdir -p "${WORK_DIR}" "${OUTPUT_DIR}"

# Download base.txz if not cached
CACHE_FILE="${WORK_DIR}/base-${VERSION}.txz"
if [ ! -f "${CACHE_FILE}" ]; then
    echo ""
    echo "[1/5] Downloading FreeBSD ${RELEASE} base.txz..."
    curl -L -o "${CACHE_FILE}" "${BASE_URL}/base.txz"
else
    echo ""
    echo "[1/5] Using cached base.txz"
fi

# Build full image (just repackaged for consistency)
echo ""
echo "[2/5] Building freebsd:${VERSION} (full)..."
FULL_DIR="${WORK_DIR}/full-${VERSION}"
rm -rf "${FULL_DIR}"
mkdir -p "${FULL_DIR}"
echo "  Extracting..."
tar -xJf "${CACHE_FILE}" -C "${FULL_DIR}"
echo "  Packaging..."
cd "${FULL_DIR}"
tar -cJf "${OUTPUT_DIR}/freebsd-${VERSION}-full.txz" .
FULL_SIZE=$(du -sh "${OUTPUT_DIR}/freebsd-${VERSION}-full.txz" | cut -f1)
echo "  Created: freebsd-${VERSION}-full.txz (${FULL_SIZE})"

# Build minimal image
echo ""
echo "[3/5] Building freebsd:${VERSION}-minimal..."
MINIMAL_DIR="${WORK_DIR}/minimal-${VERSION}"
rm -rf "${MINIMAL_DIR}"
cp -a "${FULL_DIR}" "${MINIMAL_DIR}"
cd "${MINIMAL_DIR}"

echo "  Removing documentation..."
rm -rf usr/share/doc usr/share/man usr/share/info
rm -rf usr/share/examples usr/share/misc/*.gz

echo "  Removing debug symbols..."
rm -rf usr/lib/debug

echo "  Removing non-essential locales..."
# Keep only C and en_US
find usr/share/locale -mindepth 1 -maxdepth 1 -type d ! -name 'C' ! -name 'en_US*' -exec rm -rf {} + 2>/dev/null || true

echo "  Removing games..."
rm -rf usr/games usr/share/games

echo "  Removing source/includes (keep minimal)..."
rm -rf usr/include/c++
rm -rf usr/share/nls

echo "  Removing misc..."
rm -rf var/db/pkg/* var/cache/* tmp/*
rm -rf usr/share/zoneinfo/posix usr/share/zoneinfo/right

echo "  Packaging..."
tar -cJf "${OUTPUT_DIR}/freebsd-${VERSION}-minimal.txz" .
MINIMAL_SIZE=$(du -sh "${OUTPUT_DIR}/freebsd-${VERSION}-minimal.txz" | cut -f1)
echo "  Created: freebsd-${VERSION}-minimal.txz (${MINIMAL_SIZE})"

# Build rescue image (bare minimum for recovery)
echo ""
echo "[4/5] Building freebsd:rescue..."
RESCUE_DIR="${WORK_DIR}/rescue-${VERSION}"
rm -rf "${RESCUE_DIR}"
mkdir -p "${RESCUE_DIR}"

# Extract only essential directories
cd "${FULL_DIR}"
echo "  Copying rescue utilities..."

# Create directory structure
mkdir -p "${RESCUE_DIR}"/{bin,sbin,lib,libexec,etc,tmp,var,root,rescue}
mkdir -p "${RESCUE_DIR}"/usr/{bin,sbin,lib,libexec}

# Copy rescue binaries (statically linked)
if [ -d "rescue" ]; then
    cp -a rescue/* "${RESCUE_DIR}/rescue/" 2>/dev/null || true
fi

# Copy essential binaries
for bin in sh ls cat cp mv rm mkdir rmdir chmod chown ln pwd echo sleep; do
    [ -f "bin/${bin}" ] && cp -a "bin/${bin}" "${RESCUE_DIR}/bin/"
    [ -f "rescue/${bin}" ] && cp -a "rescue/${bin}" "${RESCUE_DIR}/bin/${bin}.static"
done

for sbin in init mount umount reboot halt fsck mdconfig; do
    [ -f "sbin/${sbin}" ] && cp -a "sbin/${sbin}" "${RESCUE_DIR}/sbin/"
done

# Copy essential libraries
cp -a lib/libc.so* "${RESCUE_DIR}/lib/" 2>/dev/null || true
cp -a lib/libthr.so* "${RESCUE_DIR}/lib/" 2>/dev/null || true
cp -a lib/libm.so* "${RESCUE_DIR}/lib/" 2>/dev/null || true
cp -a lib/libutil.so* "${RESCUE_DIR}/lib/" 2>/dev/null || true
cp -a lib/libcrypt.so* "${RESCUE_DIR}/lib/" 2>/dev/null || true
cp -a lib/libncursesw.so* "${RESCUE_DIR}/lib/" 2>/dev/null || true
cp -a libexec/ld-elf.so* "${RESCUE_DIR}/libexec/" 2>/dev/null || true

# Copy minimal etc
cp -a etc/passwd etc/group etc/shells etc/login.conf "${RESCUE_DIR}/etc/" 2>/dev/null || true
echo "root::0:0::0:0:Charlie &:/root:/bin/sh" > "${RESCUE_DIR}/etc/passwd"
echo "wheel:*:0:root" > "${RESCUE_DIR}/etc/group"

cd "${RESCUE_DIR}"
echo "  Packaging..."
tar -cJf "${OUTPUT_DIR}/freebsd-${VERSION}-rescue.txz" .
RESCUE_SIZE=$(du -sh "${OUTPUT_DIR}/freebsd-${VERSION}-rescue.txz" | cut -f1)
echo "  Created: freebsd-${VERSION}-rescue.txz (${RESCUE_SIZE})"

# Generate checksums
echo ""
echo "[5/5] Generating checksums..."
cd "${OUTPUT_DIR}"
sha256sum *.txz > SHA256SUMS
cat SHA256SUMS

# Summary
echo ""
echo "=============================================="
echo "  Build Complete!"
echo "=============================================="
echo ""
echo "Images created in ${OUTPUT_DIR}:"
echo "  freebsd-${VERSION}-full.txz     ${FULL_SIZE}"
echo "  freebsd-${VERSION}-minimal.txz  ${MINIMAL_SIZE}"
echo "  freebsd-${VERSION}-rescue.txz   ${RESCUE_SIZE}"
echo ""
echo "Next steps:"
echo "  1. Create GitHub release at github.com/dyber-pqc/lochs-images"
echo "  2. Upload these files to the release"
echo "  3. Tag as v${VERSION}"
echo ""
