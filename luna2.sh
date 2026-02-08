#!/bin/bash
set -e
repo init -u https://github.com/Lunaris-AOSP/android -b 16.2 --git-lfs
repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags

rm -rf device/oneplus/aston device/oneplus/sm8550-common kernel/oneplus/sm8550 \
       kernel/oneplus/sm8550-modules kernel/oneplus/sm8550-devicetrees \
       hardware/oplus hardware/dolby vendor/oneplus/aston vendor/oneplus/sm8550-common

git clone https://github.com/gaurav-paul9/android_device_oneplus_aston.git -b luna device/oneplus/aston --depth=1
git clone https://github.com/gaurav-paul9/android_device_oneplus_sm8550-common.git -b lineage-23.2 device/oneplus/sm8550-common --depth=1
git clone https://github.com/LineageOS/android_kernel_oneplus_sm8550.git -b lineage-23.2 kernel/oneplus/sm8550 --depth=1
git clone https://github.com/LineageOS/android_kernel_oneplus_sm8550-modules.git -b lineage-23.2 kernel/oneplus/sm8550-modules --depth=1
git clone https://github.com/LineageOS/android_kernel_oneplus_sm8550-devicetrees.git -b lineage-23.2 kernel/oneplus/sm8550-devicetrees --depth=1
git clone https://github.com/LineageOS/android_hardware_oplus.git -b lineage-23.2 hardware/oplus --depth=1
git clone https://github.com/inferno0230/hardware_dolby.git -b sixteen hardware/dolby --depth=1
git clone https://github.com/TheMuppets/proprietary_vendor_oneplus_aston.git -b lineage-23.2 vendor/oneplus/aston --depth=1
git clone https://github.com/TheMuppets/proprietary_vendor_oneplus_sm8550-common.git -b lineage-23.2 vendor/oneplus/sm8550-common --depth=1

# ================= videodev2.h fix ====================
VIDEO_FILE="kernel/oneplus/sm8550/include/uapi/linux/videodev2.h"

# Remove lines 60, 61, 62
sed -i '60,62d' "$VIDEO_FILE"

# Add linux/time.h at line 62
sed -i '62i #include <linux/time.h>' "$VIDEO_FILE"

. build/envsetup.sh
lunch lineage_aston-bp4a-userdebug
m bacon
