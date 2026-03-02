#!/bin/bash
#
# Lochs Application Image Builder
# Builds application images (nginx, postgresql, redis, etc.) on top of FreeBSD base
#
# Usage: ./build-app-images.sh [image-name]
# Example: ./build-app-images.sh nginx
#          ./build-app-images.sh all
#
# Prerequisites:
#   - Must be run on FreeBSD as root
#   - Run build-images.sh first (or have base-15.0.txz in build/)
#   - pkg install bash gtar
#

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGES_DIR="${SCRIPT_DIR}/images"
BUILD_DIR="${SCRIPT_DIR}/build"
OUTPUT_DIR="${SCRIPT_DIR}/output"
BASE_VERSION="15.0"
BASE_TXZ="${BUILD_DIR}/base-${BASE_VERSION}.txz"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BUILT=0
FAILED=0
SKIPPED=0

# All available application images
ALL_IMAGES="nginx postgresql redis python node go rust"

# Use gtar piped to xz (reliable on FreeBSD)
compress_image() {
    local src_dir="$1"
    local outfile="$2"
    cd "${src_dir}"
    if command -v gtar &>/dev/null; then
        gtar cf - . | xz > "${outfile}"
    else
        tar cf - . | xz > "${outfile}"
    fi
}

# Strip BSD file flags before rm
safe_rm() {
    if command -v chflags &>/dev/null; then
        chflags -R noschg "$1" 2>/dev/null || true
    fi
    rm -rf "$1"
}

usage() {
    echo "Lochs Application Image Builder"
    echo ""
    echo "Usage: $0 [image-name|all|list]"
    echo ""
    echo "Commands:"
    echo "  all           Build all application images"
    echo "  list          List available images"
    echo "  <image-name>  Build a specific image (e.g., nginx, postgresql)"
    echo ""
    echo "Available images:"
    for img in ${ALL_IMAGES}; do
        if [ -f "${IMAGES_DIR}/${img}/Lochfile" ]; then
            desc=$(grep 'LABEL description=' "${IMAGES_DIR}/${img}/Lochfile" | head -1 | sed 's/.*description="\(.*\)"/\1/')
            printf "  %-15s %s\n" "${img}" "${desc}"
        fi
    done
    echo ""
    echo "Prerequisites:"
    echo "  1. Must be run on FreeBSD as root"
    echo "  2. pkg install bash gtar"
    echo "  3. Run './build-images.sh ${BASE_VERSION}' first (or have base-${BASE_VERSION}.txz)"
}

check_prerequisites() {
    echo -e "${BLUE}[Prerequisites]${NC}"

    # Check for base archive
    if [ ! -f "${BASE_TXZ}" ]; then
        echo -e "  ${RED}Error: ${BASE_TXZ} not found.${NC}"
        echo "  Run './build-images.sh ${BASE_VERSION}' first."
        return 1
    fi
    echo -e "  ${GREEN}✓${NC} FreeBSD ${BASE_VERSION} base archive found"

    # Check for root (needed for chroot/pkg install)
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "  ${RED}Error: Must be run as root (chroot requires it)${NC}"
        echo "  Run with: sudo $0 $*"
        return 1
    fi
    echo -e "  ${GREEN}✓${NC} Running as root"

    # Check for gtar
    if ! command -v gtar &>/dev/null; then
        echo -e "  ${YELLOW}⚠${NC} gtar not found, using tar (install gtar for reliable xz compression)"
    else
        echo -e "  ${GREEN}✓${NC} gtar found"
    fi

    return 0
}

build_image() {
    local name="$1"
    local lochfile="${IMAGES_DIR}/${name}/Lochfile"

    if [ ! -f "${lochfile}" ]; then
        echo -e "  ${RED}✗${NC} Lochfile not found: ${lochfile}"
        ((FAILED++))
        return 1
    fi

    local version=$(grep 'LABEL version=' "${lochfile}" | head -1 | sed 's/.*version="\(.*\)"/\1/')
    local desc=$(grep 'LABEL description=' "${lochfile}" | head -1 | sed 's/.*description="\(.*\)"/\1/')

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Building: ${NC}${name}:${version}"
    echo -e "${BLUE}  ${desc}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Create image build directory - extract fresh from base (don't cp -a)
    local img_build="${BUILD_DIR}/app-${name}"
    safe_rm "${img_build}"
    mkdir -p "${img_build}"
    echo "  Extracting fresh base..."
    tar -xJf "${BASE_TXZ}" -C "${img_build}"
    chflags -R noschg "${img_build}" 2>/dev/null || true

    # Strip to minimal before installing packages
    echo "  Stripping base to minimal..."
    rm -rf "${img_build}/usr/share/doc" "${img_build}/usr/share/man"
    rm -rf "${img_build}/usr/share/info" "${img_build}/usr/share/examples"
    rm -rf "${img_build}/usr/lib/debug" "${img_build}/usr/include/c++"
    rm -rf "${img_build}/usr/share/nls" "${img_build}/usr/games"
    rm -rf "${img_build}/usr/share/games"
    rm -rf "${img_build}/usr/share/zoneinfo/posix" "${img_build}/usr/share/zoneinfo/right"

    # Parse and execute RUN commands from Lochfile
    echo "  Executing Lochfile commands..."
    local run_count=0

    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//')
        case "$line" in
            RUN\ *)
                cmd="${line#RUN }"
                ((run_count++))
                echo -e "  [${run_count}] ${cmd:0:72}..."

                # Mount necessary filesystems for pkg
                mount -t devfs devfs "${img_build}/dev" 2>/dev/null
                cp /etc/resolv.conf "${img_build}/etc/resolv.conf" 2>/dev/null

                chroot "${img_build}" /bin/sh -c "${cmd}"
                local rc=$?

                umount "${img_build}/dev" 2>/dev/null
                rm -f "${img_build}/etc/resolv.conf"

                if [ $rc -ne 0 ]; then
                    echo -e "    ${YELLOW}⚠ Command returned exit code ${rc}${NC}"
                fi
                ;;
            EXPOSE\ *)
                ports="${line#EXPOSE }"
                echo -e "  Ports: ${ports}"
                ;;
            VOLUME\ *)
                vol="${line#VOLUME }"
                echo -e "  Volume: ${vol}"
                mkdir -p "${img_build}/${vol}" 2>/dev/null
                ;;
        esac
    done < "${lochfile}"

    # Clean up pkg cache inside image
    rm -rf "${img_build}/var/cache/pkg/"*
    rm -rf "${img_build}/var/db/pkg/repos/"*
    rm -rf "${img_build}/tmp/"*

    # Copy Lochfile into image for metadata
    cp "${lochfile}" "${img_build}/.lochfile"

    # Check size before compression
    local dir_size=$(du -sh "${img_build}" | cut -f1)
    echo "  Image dir size: ${dir_size}"

    # Package the image
    echo "  Compressing (this takes a few minutes)..."
    local outfile="${OUTPUT_DIR}/${name}-latest-freebsd${BASE_VERSION}.txz"
    compress_image "${img_build}" "${outfile}"
    local img_size=$(du -sh "${outfile}" | cut -f1)

    echo -e "  ${GREEN}✓${NC} Created: $(basename ${outfile}) (${img_size})"
    ((BUILT++))

    return 0
}

list_images() {
    echo ""
    echo "Available Lochs Images"
    echo "======================"
    echo ""
    printf "  ${BLUE}%-15s %-10s %-12s %s${NC}\n" "IMAGE" "VERSION" "STATUS" "DESCRIPTION"
    echo "  ─────────────────────────────────────────────────────────────────"

    # Base images
    for variant in full minimal rescue; do
        local archive="${OUTPUT_DIR}/freebsd-${BASE_VERSION}-${variant}.txz"
        local status="not built"
        if [ -f "${archive}" ]; then
            status="${GREEN}ready${NC}"
        fi
        printf "  %-15s %-10s " "freebsd-${variant}" "${BASE_VERSION}"
        echo -e "${status}"
    done

    echo ""

    # Application images
    for img in ${ALL_IMAGES}; do
        if [ -f "${IMAGES_DIR}/${img}/Lochfile" ]; then
            local ver=$(grep 'LABEL version=' "${IMAGES_DIR}/${img}/Lochfile" | head -1 | sed 's/.*version="\(.*\)"/\1/')
            local desc=$(grep 'LABEL description=' "${IMAGES_DIR}/${img}/Lochfile" | head -1 | sed 's/.*description="\(.*\)"/\1/')
            local archive=$(ls "${OUTPUT_DIR}/${img}-"*".txz" 2>/dev/null | head -1)
            local status="${YELLOW}planned${NC}"
            if [ -n "${archive}" ]; then
                status="${GREEN}ready${NC}"
            fi
            printf "  %-15s %-10s " "${img}" "${ver}"
            echo -e "${status}    ${desc}"
        fi
    done
    echo ""
}

# ============================================================================
# Main
# ============================================================================

case "${1:-}" in
    ""|"-h"|"--help"|"help")
        usage
        exit 0
        ;;
    "list"|"ls")
        list_images
        exit 0
        ;;
    "all")
        echo ""
        echo "=============================================="
        echo "  Lochs Application Image Builder"
        echo "  Building ALL application images"
        echo "=============================================="
        check_prerequisites || exit 1
        for img in ${ALL_IMAGES}; do
            build_image "${img}"
        done
        ;;
    *)
        if [ ! -d "${IMAGES_DIR}/$1" ]; then
            echo -e "${RED}Error: Unknown image '$1'${NC}"
            echo "Run '$0 list' to see available images."
            exit 1
        fi
        echo ""
        echo "=============================================="
        echo "  Lochs Application Image Builder"
        echo "=============================================="
        check_prerequisites || exit 1
        build_image "$1"
        ;;
esac

# Summary
echo ""
echo "=============================================="
echo "  Build Summary"
echo "=============================================="
echo -e "  ${GREEN}Built:${NC}   ${BUILT}"
echo -e "  ${RED}Failed:${NC}  ${FAILED}"
echo -e "  ${YELLOW}Skipped:${NC} ${SKIPPED}"
echo ""

# Update checksums
if [ ${BUILT} -gt 0 ]; then
    echo "Updating checksums..."
    cd "${OUTPUT_DIR}"
    sha256sum *.txz > SHA256SUMS 2>/dev/null
    echo "Done."
fi
echo ""
