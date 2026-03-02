#!/bin/bash
#
# Lochs Image Builder
# Creates minimal FreeBSD images for the lochs-images registry
#
# Usage: ./build-images.sh [version]
# Example: ./build-images.sh 15.0
#
# On FreeBSD: pkg install bash gtar
# On Linux (CI): works with GNU tar out of the box
#

set -e

VERSION="${1:-15.0}"
RELEASE="${VERSION}-RELEASE"
ARCH="amd64"
BASE_URL="https://download.freebsd.org/releases/${ARCH}/${ARCH}/${RELEASE}"

WORK_DIR="$(pwd)/build"
OUTPUT_DIR="$(pwd)/output"

# Create a compressed .txz archive from the current directory
# Works on both Linux (GNU tar) and FreeBSD (gtar or bsdtar + xz)
create_txz() {
    local outfile="$1"
    if command -v gtar &>/dev/null; then
        gtar cf - . | xz > "${outfile}"
    elif tar --version 2>/dev/null | grep -q GNU; then
        tar -cJf "${outfile}" .
    else
        tar cf - . | xz > "${outfile}"
    fi
}

# Extract a .txz archive, suppressing FreeBSD SCHILY.fflags warnings
extract_txz() {
    local archive="$1"
    local dest="$2"
    tar -xJf "${archive}" -C "${dest}" --warning=no-unknown-keyword 2>/dev/null || \
    tar -xJf "${archive}" -C "${dest}" 2>/dev/null || \
    tar -xJf "${archive}" -C "${dest}"
}

# Strip BSD file flags before rm (FreeBSD sets schg on system binaries)
safe_rm() {
    if command -v chflags &>/dev/null; then
        chflags -R noschg "$1" 2>/dev/null || true
    fi
    rm -rf "$1"
}

# Strip BSD file flags on a directory (no-op on Linux)
strip_flags() {
    if command -v chflags &>/dev/null; then
        chflags -R noschg "$1" 2>/dev/null || true
    fi
}

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
    curl -fL -o "${CACHE_FILE}" "${BASE_URL}/base.txz"
    # Validate we got a real archive, not an HTML error page
    if file "${CACHE_FILE}" | grep -qi 'html\|text'; then
        echo "Error: Download returned HTML instead of an archive."
        echo "FreeBSD ${RELEASE} may not exist on the mirror."
        echo "Available releases: https://download.freebsd.org/releases/amd64/amd64/"
        rm -f "${CACHE_FILE}"
        exit 1
    fi
else
    echo ""
    echo "[1/5] Using cached base.txz"
fi

# Build full image
echo ""
echo "[2/5] Building freebsd:${VERSION} (full)..."
FULL_DIR="${WORK_DIR}/full-${VERSION}"
safe_rm "${FULL_DIR}"
mkdir -p "${FULL_DIR}"
echo "  Extracting..."
extract_txz "${CACHE_FILE}" "${FULL_DIR}"
strip_flags "${FULL_DIR}"
echo "  Packaging..."
cd "${FULL_DIR}"
create_txz "${OUTPUT_DIR}/freebsd-${VERSION}-full.txz"
FULL_SIZE=$(du -sh "${OUTPUT_DIR}/freebsd-${VERSION}-full.txz" | cut -f1)
echo "  Created: freebsd-${VERSION}-full.txz (${FULL_SIZE})"

# Build minimal image (extract fresh from base, don't cp -a)
echo ""
echo "[3/5] Building freebsd:${VERSION}-minimal..."
MINIMAL_DIR="${WORK_DIR}/minimal-${VERSION}"
safe_rm "${MINIMAL_DIR}"
mkdir -p "${MINIMAL_DIR}"
echo "  Extracting fresh base..."
extract_txz "${CACHE_FILE}" "${MINIMAL_DIR}"
strip_flags "${MINIMAL_DIR}"
cd "${MINIMAL_DIR}"

echo "  Removing documentation..."
rm -rf usr/share/doc usr/share/man usr/share/info
rm -rf usr/share/examples usr/share/misc/*.gz

echo "  Removing debug symbols..."
rm -rf usr/lib/debug

echo "  Removing non-essential locales..."
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
create_txz "${OUTPUT_DIR}/freebsd-${VERSION}-minimal.txz"
MINIMAL_SIZE=$(du -sh "${OUTPUT_DIR}/freebsd-${VERSION}-minimal.txz" | cut -f1)
echo "  Created: freebsd-${VERSION}-minimal.txz (${MINIMAL_SIZE})"

# Build rescue image (bare minimum for recovery)
echo ""
echo "[4/5] Building freebsd:rescue..."
RESCUE_DIR="${WORK_DIR}/rescue-${VERSION}"
safe_rm "${RESCUE_DIR}"

# Create directory structure (no brace expansion for sh compatibility)
mkdir -p "${RESCUE_DIR}/bin"
mkdir -p "${RESCUE_DIR}/sbin"
mkdir -p "${RESCUE_DIR}/lib"
mkdir -p "${RESCUE_DIR}/libexec"
mkdir -p "${RESCUE_DIR}/etc"
mkdir -p "${RESCUE_DIR}/tmp"
mkdir -p "${RESCUE_DIR}/var"
mkdir -p "${RESCUE_DIR}/root"
mkdir -p "${RESCUE_DIR}/rescue"
mkdir -p "${RESCUE_DIR}/usr/bin"
mkdir -p "${RESCUE_DIR}/usr/sbin"
mkdir -p "${RESCUE_DIR}/usr/lib"
mkdir -p "${RESCUE_DIR}/usr/libexec"

cd "${FULL_DIR}"
echo "  Copying rescue utilities..."

# Copy rescue binaries (statically linked)
if [ -d "rescue" ]; then
    cp -a rescue/* "${RESCUE_DIR}/rescue/" 2>/dev/null || true
fi

# Copy essential binaries
for bin in sh ls cat cp mv rm mkdir rmdir chmod chown ln pwd echo sleep; do
    [ -f "bin/${bin}" ] && cp -a "bin/${bin}" "${RESCUE_DIR}/bin/"
done

for sbin in init mount umount reboot halt fsck mdconfig; do
    [ -f "sbin/${sbin}" ] && cp -a "sbin/${sbin}" "${RESCUE_DIR}/sbin/"
done

# Copy essential libraries
for lib in libc.so* libthr.so* libm.so* libutil.so* libcrypt.so* libsys.so* libncursesw.so*; do
    cp -a lib/${lib} "${RESCUE_DIR}/lib/" 2>/dev/null || true
done
cp -a libexec/ld-elf.so* "${RESCUE_DIR}/libexec/" 2>/dev/null || true

# Minimal etc
echo "root::0:0::0:0:Charlie &:/root:/bin/sh" > "${RESCUE_DIR}/etc/passwd"
echo "wheel:*:0:root" > "${RESCUE_DIR}/etc/group"

cd "${RESCUE_DIR}"
echo "  Packaging..."
create_txz "${OUTPUT_DIR}/freebsd-${VERSION}-rescue.txz"
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
