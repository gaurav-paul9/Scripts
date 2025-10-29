#!/bin/bash
#
# AxionOS Automated Build Script with Telegram Notifications + PixelDrain Upload
#

# ========== TELEGRAM SETUP ==========
BOT_TOKEN="8010620197:AAHZPATLJ-AsXPdLttwR65ozmjFpMgLzUV8"
CHAT_ID="1249290479"

send_telegram_message() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"          -d chat_id="${CHAT_ID}"          -d parse_mode="Markdown"          -d text="$message" > /dev/null
}

# ========== PIXELDRAIN UPLOAD SETUP ==========
PIXELDRAIN_API_KEY="3dad7002-43a2-4f24-9b29-2b90fe8a5591"

upload_to_pixeldrain() {
    local file_path="$1"

    if [ ! -f "$file_path" ]; then
        send_telegram_message "❌ ROM zip not found at: $file_path"
        return 1
    fi

    send_telegram_message "☁️ Uploading ROM to PixelDrain..."

    local response=$(curl -s -H "Authorization: ${PIXELDRAIN_API_KEY}" -F "file=@${file_path}" https://pixeldrain.com/api/file)
    local file_id=$(echo "$response" | grep -o '"id":"[^"]*' | cut -d'"' -f4)

    if [ -n "$file_id" ]; then
        local file_url="https://pixeldrain.com/u/${file_id}"
        send_telegram_message "✅ ROM uploaded successfully!\n📎 [Download Link](${file_url})"
    else
        send_telegram_message "❌ Upload failed! Could not get file link."
    fi
}

# ========== BUILD START ==========
send_telegram_message "🚀 *AxionOS Build Started!*"

# ========== REPO INIT ==========
send_telegram_message "📦 Initializing repo..."
repo init -u https://github.com/AxionAOSP/android.git -b lineage-23.0 --git-lfs || {
    send_telegram_message "❌ Repo init failed!"
    exit 1
}

# ========== CLEAN PREBUILTS ==========
send_telegram_message "🧹 Cleaning old prebuilts..."
rm -rf prebuilts/clang/host/linux-x86

# ========== RESYNC ==========
send_telegram_message "🔁 Running resync script..."
/opt/crave/resync.sh || {
    send_telegram_message "❌ Resync failed!"
    exit 1
}

# ========== CLONING DEVICE TREE & DEPENDENCIES ==========
send_telegram_message "📥 Cloning device, kernel, and vendor sources..."

git clone https://github.com/gaurav-paul9/android_device_oneplus_aston.git -b lineage-23.0 device/oneplus/aston --depth=1
git clone https://github.com/LineageOS/android_device_oneplus_sm8550-common.git -b lineage-23.0 device/oneplus/sm8550-common --depth=1
git clone https://github.com/gaurav-paul9/android_kernel_oneplus_sm8550.git -b lineage-23.0 kernel/oneplus/sm8550 --depth=1
git clone https://github.com/LineageOS/android_kernel_oneplus_sm8550-modules.git -b lineage-23.0 kernel/oneplus/sm8550-modules --depth=1
git clone https://github.com/LineageOS/android_kernel_oneplus_sm8550-devicetrees.git -b lineage-23.0 kernel/oneplus/sm8550-devicetrees --depth=1
git clone https://github.com/LineageOS/android_hardware_oplus.git -b lineage-23.0 hardware/oplus --depth=1
git clone https://github.com/TheMuppets/proprietary_vendor_oneplus_aston.git -b lineage-23.0 vendor/oneplus/aston --depth=1
git clone https://github.com/TheMuppets/proprietary_vendor_oneplus_sm8550-common.git -b lineage-23.0 vendor/oneplus/sm8550-common --depth=1

send_telegram_message "✅ All sources cloned successfully!"

# ========== ENVIRONMENT SETUP ==========
send_telegram_message "🧩 Setting up build environment..."
. build/envsetup.sh || {
    send_telegram_message "❌ Environment setup failed!"
    exit 1
}

# ========== AXION BUILD STEPS ==========
send_telegram_message "⚙️ Starting Axion build..."
gk -s
axion aston gms core
m installclean

# ========== BUILD START ==========
send_telegram_message "🏗️ Build process started..."
ax -br -j$(nproc --all)
if [ $? -ne 0 ]; then
    send_telegram_message "💥 Build failed! Check the logs on server."
    exit 1
fi

# ========== UPLOAD ROM ==========
ROM_PATH=$(find out/target/product/aston -maxdepth 1 -type f -name "axion*.zip" | head -n 1)

if [ -f "$ROM_PATH" ]; then
    upload_to_pixeldrain "$ROM_PATH"
else
    send_telegram_message "⚠️ Build finished but no ROM zip found!"
fi

# ========== SUCCESS ==========
send_telegram_message "🎉 *AxionOS Build Completed Successfully!* ✅"
