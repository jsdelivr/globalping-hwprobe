#!/bin/bash
# Update kernel recipe to use specific SRCREV instead of AUTOREV
# This ensures reproducible builds with a known-working kernel version

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="${SCRIPT_DIR}/sources"
KERNEL_DIR="${SOURCES_DIR}/kernel-rockchip"
RECIPE_FILE="${SCRIPT_DIR}/meta-nanopi-zero2/recipes-kernel/linux/linux-friendlyarm_6.1.bb"

echo "============================================"
echo "Update Kernel SRCREV"
echo "============================================"
echo

# Check if kernel source exists
if [ ! -d "${KERNEL_DIR}/.git" ]; then
    echo "ERROR: Kernel source not found at ${KERNEL_DIR}"
    echo "Please run ./setup-friendlyelec-sources.sh first"
    exit 1
fi

# Check if recipe exists
if [ ! -f "${RECIPE_FILE}" ]; then
    echo "ERROR: Kernel recipe not found at ${RECIPE_FILE}"
    exit 1
fi

# Get current kernel commit
cd "${KERNEL_DIR}"
CURRENT_COMMIT=$(git rev-parse HEAD)
CURRENT_COMMIT_SHORT=$(git rev-parse --short HEAD)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
COMMIT_DATE=$(git log -1 --format=%cd --date=short)
COMMIT_SUBJECT=$(git log -1 --format=%s)
KERNEL_VERSION=$(git describe --tags 2>/dev/null || echo "unknown")

echo "Current kernel information:"
echo "  Repository: ${KERNEL_DIR}"
echo "  Branch: ${CURRENT_BRANCH}"
echo "  Commit: ${CURRENT_COMMIT}"
echo "  Short: ${CURRENT_COMMIT_SHORT}"
echo "  Date: ${COMMIT_DATE}"
echo "  Version: ${KERNEL_VERSION}"
echo "  Subject: ${COMMIT_SUBJECT}"
echo

# Check current recipe SRCREV
CURRENT_SRCREV=$(grep "^SRCREV" "${RECIPE_FILE}" | cut -d'"' -f2 || echo "not found")
echo "Current recipe SRCREV: ${CURRENT_SRCREV}"
echo

# Ask for confirmation
read -p "Update recipe to use commit ${CURRENT_COMMIT_SHORT}? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Backup original recipe
cp "${RECIPE_FILE}" "${RECIPE_FILE}.bak"
echo "Backup created: ${RECIPE_FILE}.bak"

# Update SRCREV in recipe
if grep -q "^SRCREV.*=.*\${AUTOREV}" "${RECIPE_FILE}"; then
    # Replace AUTOREV with specific commit
    sed -i "s/^SRCREV.*=.*\${AUTOREV}.*/SRCREV = \"${CURRENT_COMMIT}\"/" "${RECIPE_FILE}"
    echo "✓ Updated SRCREV from AUTOREV to ${CURRENT_COMMIT}"
elif grep -q "^SRCREV" "${RECIPE_FILE}"; then
    # Replace existing commit with new one
    sed -i "s/^SRCREV.*/SRCREV = \"${CURRENT_COMMIT}\"/" "${RECIPE_FILE}"
    echo "✓ Updated SRCREV to ${CURRENT_COMMIT}"
else
    echo "ERROR: Could not find SRCREV in recipe"
    exit 1
fi

# Add comment with kernel version info
if ! grep -q "# Kernel version pinned on" "${RECIPE_FILE}"; then
    # Add comment before SRCREV line
    sed -i "/^SRCREV/i # Kernel version pinned on ${COMMIT_DATE} (${KERNEL_VERSION})" "${RECIPE_FILE}"
    sed -i "/^# Kernel version pinned/i # Commit: ${COMMIT_SUBJECT}" "${RECIPE_FILE}"
fi

echo
echo "Updated recipe:"
grep -A 2 "SRCREV" "${RECIPE_FILE}"
echo

# Create version record
VERSION_FILE="${SCRIPT_DIR}/kernel-version.txt"
cat > "${VERSION_FILE}" << EOF
Kernel Version Record
====================
Updated: $(date)

Repository: https://github.com/friendlyarm/kernel-rockchip.git
Branch: ${CURRENT_BRANCH}
Commit: ${CURRENT_COMMIT}
Short: ${CURRENT_COMMIT_SHORT}
Date: ${COMMIT_DATE}
Version: ${KERNEL_VERSION}
Subject: ${COMMIT_SUBJECT}

Recipe: ${RECIPE_FILE}
EOF

echo "Version information saved to: ${VERSION_FILE}"
echo

echo "============================================"
echo "Update Complete!"
echo "============================================"
echo
echo "The kernel recipe has been updated to use a pinned commit."
echo
echo "Changes made:"
echo "  - SRCREV now points to: ${CURRENT_COMMIT_SHORT}"
echo "  - Backup created: ${RECIPE_FILE}.bak"
echo "  - Version recorded: ${VERSION_FILE}"
echo
echo "Next steps:"
echo "  1. Review the changes:"
echo "     git diff ${RECIPE_FILE}"
echo
echo "  2. Test the build:"
echo "     source sources/poky/oe-init-build-env build"
echo "     bitbake -c cleansstate linux-friendlyarm"
echo "     bitbake core-image-minimal"
echo
echo "  3. If successful, commit the changes:"
echo "     git add ${RECIPE_FILE} ${VERSION_FILE}"
echo "     git commit -m 'Pin kernel to commit ${CURRENT_COMMIT_SHORT}'"
echo
echo "To revert to AUTOREV:"
echo "  cp ${RECIPE_FILE}.bak ${RECIPE_FILE}"
echo
