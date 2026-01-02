#!/bin/bash

# =================================================================
#                     Axion Build Script
# =================================================================
#
# Stop the script immediately if any command fails


# =======================
#   SETUP & PRE-CHECKS
# =======================



# === Exports ===
BUILD_START_TIME=$(date +%s)
export BUILD_USERNAME=gaurav
export BUILD_HOSTNAME=crave


# =======================
#   1. CLEANUP SECTION
# =======================

echo "Cleaning up cloned repositories..."
rm -rf device/oneplus/aston
rm -rf device/oneplus/sm8550-common
rm -rf kernel/oneplus/sm8550
rm -rf kernel/oneplus/sm8550-modules
rm -rf kernel/oneplus/sm8550-devicetrees
rm -rf hardware/oplus
rm -rf hardware/dolby
rm -rf vendor/oneplus/aston
rm -rf vendor/oneplus/sm8550-common
rm -rf packages/apps/GameBar
rm -rf .repo
rm -rf vendor/revanced
rm -rf vendor/euclid

echo "Performing selective cleanup of 'out' directory..."
rm -rf out/target/product/aston/system
rm -rf out/target/product/aston/product
echo "Cleanup finished."

# =======================
#   2. REPO INITIALIZATION & SYNC
# =======================
echo "Initializing infinity repository..."
repo init -u https://github.com/AxionAOSP/android.git -b lineage-23.1 --git-lfs


echo "Syncing sources..."
if [ -f "/opt/crave/resync.sh" ]; then
    /opt/crave/resync.sh
else
    repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync
fi


# =======================
#   4. CLONING ADDITIONAL REPOSITORIES
# =======================
echo "Cloning additional repositories..."
git clone https://github.com/gaurav-paul9/android_device_oneplus_aston.git -b axion device/oneplus/aston --depth=1
git clone https://github.com/gaurav-paul9/android_device_oneplus_sm8550-common-qpr1.git -b sixteen-qpr1 device/oneplus/sm8550-common --depth=1
git clone https://github.com/OnePlus12R-development/android_kernel_oneplus_sm8550.git -b sixteen-qpr1 kernel/oneplus/sm8550 --depth=1
git clone https://github.com/OnePlus12R-development/android_kernel_oneplus_sm8550-modules.git -b sixteen-qpr1 kernel/oneplus/sm8550-modules --depth=1
git clone https://github.com/OnePlus12R-development/android_kernel_oneplus_sm8550-devicetrees.git -b sixteen-qpr1 kernel/oneplus/sm8550-devicetrees --depth=1
git clone https://github.com/inferno0230/android_hardware_oplus.git -b sixteen-qpr1 hardware/oplus --depth=1
git clone https://github.com/inferno0230/hardware_dolby.git -b sixteen-qpr1 hardware/dolby --depth=1
git clone https://gitlab.com/playground0230/vendor_oneplus_aston.git -b sixteen-qpr1 vendor/oneplus/aston --depth=1
git clone https://gitlab.com/playground0230/vendor_oneplus_sm8550-common.git -b sixteen-qpr1 vendor/oneplus/sm8550-common --depth=1


# Some Patches
echo "Applying Some Patches"
# ================= genfs_contexts fix =================
# Comment line 66 to avoid duplicate genfs entry
sed -i '66s/^/#/' \
device/qcom/sepolicy_vndr/sm8550/generic/vendor/common/genfs_contexts


# ================= videodev2.h fix ====================
VIDEO_FILE="kernel/oneplus/sm8550/include/uapi/linux/videodev2.h"

# Remove lines 60, 61, 62
sed -i '60,62d' "$VIDEO_FILE"

# Add linux/time.h at line 62
sed -i '62i #include <linux/time.h>' "$VIDEO_FILE"


# =======================
#   6. BUILD THE ROM
# =======================
echo "Starting the build process..."
. build/envsetup.sh
gk -s
echo "Starting the main build..."
axion aston gms core
ax -br

echo "Script finished."

# Unset the trap explicitly for a clean successful exit
trap - EXIT
