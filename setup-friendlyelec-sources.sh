#!/bin/bash
# Setup FriendlyElec source repositories for local builds
# This script clones all necessary repositories and records their versions

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="${SCRIPT_DIR}/sources"

echo "============================================"
echo "FriendlyElec Sources Setup"
echo "============================================"
echo

# Create sources directory
mkdir -p "${SOURCES_DIR}"
cd "${SOURCES_DIR}"

# Function to clone or update repository
clone_or_update() {
    local repo_url=$1
    local repo_dir=$2
    local branch=$3

    if [ -d "${repo_dir}/.git" ]; then
        echo "Repository ${repo_dir} already exists, updating..."
        cd "${repo_dir}"
        git fetch origin
        git checkout ${branch}
        git pull origin ${branch}
        cd ..
    else
        echo "Cloning ${repo_url} (branch: ${branch})..."
        git clone -b ${branch} ${repo_url} ${repo_dir}
    fi
}

# 1. Clone U-Boot for RK3528 (NanoPi6 series)
echo "=== Setting up U-Boot (nanopi6-v2017.09 branch) ==="
clone_or_update \
    "https://github.com/friendlyarm/uboot-rockchip.git" \
    "uboot-rockchip" \
    "nanopi6-v2017.09"
echo

# 2. Clone Rockchip binary tools (nanopi_m5 branch has RK3528 support)
echo "=== Setting up rkbin (Rockchip binary tools) ==="
clone_or_update \
    "https://github.com/friendlyarm/rkbin.git" \
    "rkbin" \
    "nanopi_m5"
echo

# 3. Clone Kernel (for reference, Yocto builds this)
echo "=== Setting up Kernel (nanopi6-v6.1.y branch) ==="
clone_or_update \
    "https://github.com/friendlyarm/kernel-rockchip.git" \
    "kernel-rockchip" \
    "nanopi6-v6.1.y"
echo

# 4. Record all versions
echo "=== Recording version information ==="

cat > "${SOURCES_DIR}/versions.txt" << EOF
FriendlyElec Sources Version Information
Generated: $(date)
========================================

EOF

for repo in uboot-rockchip rkbin kernel-rockchip; do
    if [ -d "${repo}/.git" ]; then
        echo "--- ${repo} ---" >> versions.txt
        cd "${repo}"
        echo "Branch: $(git rev-parse --abbrev-ref HEAD)" >> ../versions.txt
        echo "Commit: $(git rev-parse HEAD)" >> ../versions.txt
        echo "Date: $(git log -1 --format=%cd)" >> ../versions.txt
        echo "Subject: $(git log -1 --format=%s)" >> ../versions.txt
        echo >> ../versions.txt
        cd ..
    fi
done

# 5. Create JSON manifest
echo "=== Creating build manifest ==="

cat > "${SOURCES_DIR}/build-manifest.json" << EOF
{
  "generated": "$(date -Iseconds)",
  "components": {
    "uboot": {
      "repository": "https://github.com/friendlyarm/uboot-rockchip.git",
      "branch": "$(cd uboot-rockchip && git rev-parse --abbrev-ref HEAD)",
      "commit": "$(cd uboot-rockchip && git rev-parse HEAD)",
      "commit_short": "$(cd uboot-rockchip && git rev-parse --short HEAD)",
      "version": "2017.09"
    },
    "rkbin": {
      "repository": "https://github.com/friendlyarm/rkbin.git",
      "branch": "$(cd rkbin && git rev-parse --abbrev-ref HEAD)",
      "commit": "$(cd rkbin && git rev-parse HEAD)",
      "commit_short": "$(cd rkbin && git rev-parse --short HEAD)"
    },
    "kernel": {
      "repository": "https://github.com/friendlyarm/kernel-rockchip.git",
      "branch": "$(cd kernel-rockchip && git rev-parse --abbrev-ref HEAD)",
      "commit": "$(cd kernel-rockchip && git rev-parse HEAD)",
      "commit_short": "$(cd kernel-rockchip && git rev-parse --short HEAD)",
      "version": "6.1.118"
    }
  }
}
EOF

echo
echo "============================================"
echo "Setup Complete!"
echo "============================================"
echo
echo "Sources location: ${SOURCES_DIR}"
echo
echo "Repositories cloned (into sources/):"
echo "  - sources/uboot-rockchip  (branch: nanopi6-v2017.09)"
echo "  - sources/rkbin           (branch: nanopi_m5)"
echo "  - sources/kernel-rockchip (branch: nanopi6-v6.1.y)"
echo
echo "Version information saved to:"
echo "  - ${SOURCES_DIR}/versions.txt"
echo "  - ${SOURCES_DIR}/build-manifest.json"
echo
echo "Next steps:"
echo "  1. Review versions.txt to verify commits"
echo "  2. Run ./build-uboot-from-source.sh to build U-Boot"
echo "  3. Run ./update-kernel-srcrev.sh to pin kernel version"
echo
