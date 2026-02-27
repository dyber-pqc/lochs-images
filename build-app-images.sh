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
#   - BSDulator must be built and available as ./bsdulator or in PATH
#   - FreeBSD base image must exist (run build-images.sh first)
#

set +e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
IMAGES_DIR="${SCRIPT_DIR}/images"
BUILD_DIR="${SCRIPT_DIR}/build"
OUTPUT_DIR="${SCRIPT_DIR}/output"
BASE_VERSION="15.0"

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
    echo "  1. Run './build-images.sh ${BASE_VERSION}' first to create base images"
    echo "  2. BSDulator must be available (run 'make' in the bsdulator repo)"
}

check_prerequisites() {
    echo -e "${BLUE}[Prerequisites]${NC}"

    # Check for base image
    BASE_DIR="${BUILD_DIR}/minimal-${BASE_VERSION}"
    if [ ! -d "${BASE_DIR}" ]; then
        BASE_ARCHIVE="${OUTPUT_DIR}/freebsd-${BASE_VERSION}-minimal.txz"
        if [ -f "${BASE_ARCHIVE}" ]; then
            echo "  Extracting base image..."
            mkdir -p "${BASE_DIR}"
            tar -xJf "${BASE_ARCHIVE}" -C "${BASE_DIR}"
        else
            echo -e "  ${RED}Error: FreeBSD base image not found.${NC}"
            echo "  Run './build-images.sh ${BASE_VERSION}' first."
            return 1
        fi
    fi
    echo -e "  ${GREEN}✓${NC} FreeBSD ${BASE_VERSION} base image ready"

    # Check for bsdulator
    BSDULATOR=""
    if [ -x "${SCRIPT_DIR}/../bsdulator" ]; then
        BSDULATOR="${SCRIPT_DIR}/../bsdulator"
    elif command -v bsdulator &>/dev/null; then
        BSDULATOR="$(command -v bsdulator)"
    fi

    if [ -n "${BSDULATOR}" ]; then
        echo -e "  ${GREEN}✓${NC} BSDulator found: ${BSDULATOR}"
    else
        echo -e "  ${YELLOW}⚠${NC} BSDulator not found - will use chroot method instead"
    fi

    # Check for root (needed for chroot/pkg install)
    if [ "$EUID" -ne 0 ]; then
        echo -e "  ${YELLOW}⚠${NC} Not running as root - some builds may fail"
        echo "  Run with: sudo $0 $*"
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

    # Create image build directory from base
    local img_build="${BUILD_DIR}/app-${name}"
    rm -rf "${img_build}"
    echo "  Copying base image..."
    cp -a "${BUILD_DIR}/minimal-${BASE_VERSION}" "${img_build}"

    # Parse and execute RUN commands from Lochfile
    echo "  Executing Lochfile commands..."
    local run_count=0
    local failed=0

    while IFS= read -r line; do
        # Skip comments, empty lines, and non-RUN directives
        line=$(echo "$line" | sed 's/^[[:space:]]*//')
        case "$line" in
            RUN\ *)
                cmd="${line#RUN }"
                ((run_count++))
                echo -e "  [${run_count}] ${cmd:0:72}..."

                # Execute in chroot
                if [ "$EUID" -eq 0 ]; then
                    # Mount necessary filesystems for pkg
                    mount -t devfs devfs "${img_build}/dev" 2>/dev/null
                    cp /etc/resolv.conf "${img_build}/etc/resolv.conf" 2>/dev/null

                    chroot "${img_build}" /bin/sh -c "${cmd}" > /dev/null 2>&1
                    local rc=$?

                    umount "${img_build}/dev" 2>/dev/null
                    rm -f "${img_build}/etc/resolv.conf"

                    if [ $rc -ne 0 ]; then
                        echo -e "    ${YELLOW}⚠ Command returned exit code ${rc} (may be OK)${NC}"
                    fi
                else
                    echo -e "    ${YELLOW}⚠ Skipped (requires root)${NC}"
                    failed=1
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

    if [ $failed -eq 1 ] && [ "$EUID" -ne 0 ]; then
        echo -e "  ${YELLOW}⚠${NC} Skipped package installation (need root)"
        echo "  Creating skeleton image with Lochfile metadata only..."
    fi

    # Copy Lochfile into image for metadata
    cp "${lochfile}" "${img_build}/.lochfile"

    # Package the image
    echo "  Packaging..."
    cd "${img_build}"
    local outfile="${OUTPUT_DIR}/${name}-${version}-freebsd${BASE_VERSION}.txz"
    tar -cJf "${outfile}" . 2>/dev/null
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
