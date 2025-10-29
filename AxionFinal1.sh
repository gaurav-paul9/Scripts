#!/bin/bash
#
# AxionOS Automated Build Script (v3)
# Features:
#  → Hidden .env secrets
#  → Strict error handling (stop on failure)
#  → Telegram notifications
#  → PixelDrain upload
#  → Detailed success message
#  → Automatic error log upload if build fails
#

set -eEuo pipefail

# ========== LOAD SECRETS ==========
SECRETS_FILE=""
if [ -f ".env" ]; then
  SECRETS_FILE=".env"
elif [ -f ".env/secrets.env" ]; then
  SECRETS_FILE=".env/secrets.env"
fi

if [ -z "$SECRETS_FILE" ]; then
  echo "❌ No secrets file found (.env or .env/secrets.env)"
  exit 1
fi

set -o allexport
source "$SECRETS_FILE"
set +o allexport

# Validate secrets
[ -z "${TG_BOT_TOKEN:-}" ] && echo "Missing TG_BOT_TOKEN" && exit 1
[ -z "${TG_CHAT_ID:-}" ] && echo "Missing TG_CHAT_ID" && exit 1
[ -z "${PIXELDRAIN_API_KEY:-}" ] && echo "Missing PIXELDRAIN_API_KEY" && exit 1

# ========== TELEGRAM FUNCTION ==========
send_telegram() {
  local text="$1"
  curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
       -d chat_id="${TG_CHAT_ID}" \
       -d parse_mode="Markdown" \
       --data-urlencode "text=${text}" > /dev/null
}

# ========== FAILURE HANDLER ==========
on_error() {
  local exit_code=$?
  local failed_command="${BASH_COMMAND}"

  send_telegram "💥 *AxionOS Build Failed!*\n\n🧩 Command that failed:\n\`${failed_command}\`\n\n❌ Exit Code: ${exit_code}\n🕓 Time: $(date '+%Y-%m-%d %H:%M:%S')\n\n📄 Attempting to send error log..."

  ERROR_LOG=$(find out -maxdepth 1 -type f -name "error*" | head -n 1)

  if [ -n "$ERROR_LOG" ]; then
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
         -F chat_id="${TG_CHAT_ID}" \
         -F caption="🧾 Error log attached (${ERROR_LOG})" \
         -F document=@"${ERROR_LOG}" > /dev/null
  else
    send_telegram "⚠️ No error log found inside out/ directory!"
  fi

  exit $exit_code
}
trap on_error ERR

# ========== START BUILD ==========
BUILD_START=$(date +%s)
send_telegram "🚀 *AxionOS Build Started!*\n\nPreparing environment and syncing sources..."

# ========== REPO INIT & SYNC ==========
send_telegram "📦 Initializing repo..."
repo init -u https://github.com/AxionAOSP/android.git -b lineage-23.0 --git-lfs

send_telegram "🔁 Syncing sources..."
repo sync -c --force-sync --no-clone-bundle --no-tags -j$(nproc --all)

# ========== CLEANUP & CLONE ==========
send_telegram "🧹 Cleaning old prebuilts and cloning device sources..."
rm -rf prebuilts/clang/host/linux-x86

git clone https://github.com/gaurav-paul9/android_device_oneplus_aston.git -b lineage-23.0 device/oneplus/aston --depth=1
git clone https://github.com/LineageOS/android_device_oneplus_sm8550-common.git -b lineage-23.0 device/oneplus/sm8550-common --depth=1
git clone https://github.com/gaurav-paul9/android_kernel_oneplus_sm8550.git -b lineage-23.0 kernel/oneplus/sm8550 --depth=1
git clone https://github.com/TheMuppets/proprietary_vendor_oneplus_aston.git -b lineage-23.0 vendor/oneplus/aston --depth=1
git clone https://github.com/TheMuppets/proprietary_vendor_oneplus_sm8550-common.git -b lineage-23.0 vendor/oneplus/sm8550-common --depth=1

# ========== SETUP & BUILD ==========
send_telegram "🧩 Setting up build environment..."
. build/envsetup.sh

send_telegram "🏗️ Building AxionOS for OnePlus 12R (Aston)..."
gk -s
axion aston gms core
m installclean

# Log the entire build output
ax -br -j$(nproc --all) 2>&1 | tee out/error.log

# ========== UPLOAD ROM ==========
BUILD_END=$(date +%s)
DURATION=$((BUILD_END - BUILD_START))
HOURS=$((DURATION / 3600))
MINUTES=$(((DURATION % 3600) / 60))
SECONDS=$((DURATION % 60))
BUILD_TIME=$(printf "%dh:%dm:%ds" $HOURS $MINUTES $SECONDS)

ROM_PATH=$(find out/target/product/aston -type f -name "axion*.zip" | sort | tail -n1)
[ -z "$ROM_PATH" ] && { send_telegram "⚠️ No ROM zip found!"; exit 1; }

ROM_NAME=$(basename "$ROM_PATH")
FILE_SIZE=$(du -h "$ROM_PATH" | cut -f1)
MD5_SUM=$(md5sum "$ROM_PATH" | awk '{print $1}')
UPLOAD_TIME=$(date '+%Y-%m-%d %H:%M')

send_telegram "☁️ Uploading *${ROM_NAME}* (${FILE_SIZE}) to PixelDrain..."
UPLOAD_JSON=$(curl -s -u ":${PIXELDRAIN_API_KEY}" -F "file=@${ROM_PATH}" https://pixeldrain.com/api/file)
FILE_ID=$(echo "$UPLOAD_JSON" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
[ -z "$FILE_ID" ] && { send_telegram "❌ Upload failed!"; exit 1; }
DL_LINK="https://pixeldrain.com/u/${FILE_ID}"

# ========== SUCCESS MESSAGE ==========
DEVICE_NAME="OnePlus 12R (Aston)"
send_telegram "🎉 *AxionOS Upload Complete for ${DEVICE_NAME}!*

🕓 *Build Duration:* \`${BUILD_TIME}\`
📎 *Filename:* \`${ROM_NAME}\`
📦 *Size:* ${FILE_SIZE}
🔑 *MD5:* \`${MD5_SUM}\`
🗓️ *Uploaded:* ${UPLOAD_TIME}
🔗 [Download Link](${DL_LINK})"

send_telegram "✅ *Build Completed Successfully!* 🎯"
