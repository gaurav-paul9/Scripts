#!/bin/bash
#
# AxionOS Automated Build Script (v4)
# - Loads secrets from hidden .env/.env/secrets.env
# - Stops immediately on any error
# - Sends beautiful Telegram notifications (start, progress, success, failure)
# - Uploads ROM to PixelDrain and shares link
# - On failure uploads error log (out/error*.log)
#
set -eEuo pipefail

# -------------------- Load secrets --------------------
SECRETS_FILE=""
if [ -f ".env" ]; then
  SECRETS_FILE=".env"
elif [ -f ".env/secrets.env" ]; then
  SECRETS_FILE=".env/secrets.env"
fi

if [ -z "$SECRETS_FILE" ]; then
  echo "❌ No secrets file found (.env or .env/secrets.env). Please create it and re-run."
  exit 1
fi

# shellcheck disable=SC1090
set -o allexport
source "$SECRETS_FILE"
set +o allexport

# Validate required secrets
missing=0
[ -z "${TG_BOT_TOKEN:-}" ] && echo "Missing TG_BOT_TOKEN" && missing=1
[ -z "${TG_CHAT_ID:-}" ] && echo "Missing TG_CHAT_ID" && missing=1
[ -z "${PIXELDRAIN_API_KEY:-}" ] && echo "Missing PIXELDRAIN_API_KEY" && missing=1
if [ "$missing" -ne 0 ]; then
  exit 1
fi

# -------------------- Helpers --------------------
send_telegram() {
  local message="$1"
  # Use data-urlencode to preserve newlines and special characters
  curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
       -d chat_id="${TG_CHAT_ID}" \
       -d parse_mode="Markdown" \
       --data-urlencode "text=${message}" > /dev/null || true
}

send_telegram_document() {
  local file_path="$1"
  local caption="$2"
  if [ -f "${file_path}" ]; then
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
         -F chat_id="${TG_CHAT_ID}" \
         -F caption="${caption}" \
         -F document=@"${file_path}" > /dev/null || true
  else
    send_telegram "⚠️ Tried to attach file but it was not found: ${file_path}"
  fi
}

# -------------------- Failure handler --------------------
on_error() {
  local exit_code=$?
  local failed_command="${BASH_COMMAND:-unknown}"
  local now
  now=$(date '+%Y-%m-%d %H:%M:%S')

  # Pretty failure message with real newlines
  read -r -d '' fail_msg <<EOF || true
💥 *AxionOS Build — FAILURE*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️ *Failed Command:*
\`${failed_command}\`

❌ *Exit Code:* ${exit_code}
🕓 *Time:* ${now}

📄 Attempting to attach any error log from the out/ folder...
EOF

  send_telegram "${fail_msg}"

  # Find error log starting with "error" in out/ (most recent)
  ERROR_LOG=$(find out -maxdepth 1 -type f -name "error*" -printf "%T@ %p\n" 2>/dev/null | sort -n | tail -n1 | awk '{print $2}' || true)

  if [ -n "${ERROR_LOG:-}" ] && [ -f "${ERROR_LOG}" ]; then
    send_telegram_document "${ERROR_LOG}" "🧾 Build error log attached (${ERROR_LOG})"
  else
    # Also try generic build log (out/error.log from our script)
    if [ -f "out/error.log" ]; then
      send_telegram_document "out/error.log" "🧾 Build error log attached (out/error.log)"
    else
      send_telegram "⚠️ No error log found in out/ to attach."
    fi
  fi

  exit "${exit_code}"
}
trap on_error ERR

# -------------------- Build start --------------------
BUILD_START_TS=$(date +%s)
BUILD_START_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')
DEVICE_NAME="OnePlus 12R (Aston)"

read -r -d '' start_msg <<EOF || true
🚀 *AxionOS Build — Started*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 *Device:* ${DEVICE_NAME}
🕓 *Start Time:* ${BUILD_START_HUMAN}
EOF

send_telegram "${start_msg}"

# -------------------- Repo init & sync --------------------
send_telegram "📦 Initializing repo..."
repo init -u https://github.com/AxionAOSP/android.git -b lineage-23.0 --git-lfs

send_telegram "🔁 Syncing sources (this may take a while)..."
repo sync -c --force-sync --no-clone-bundle --no-tags -j$(nproc --all)

# -------------------- Cleanup & clones --------------------
send_telegram "🧹 Cleaning prebuilts and cloning device/kernel/vendor repos..."
rm -rf prebuilts/clang/host/linux-x86 || true

git clone https://github.com/gaurav-paul9/android_device_oneplus_aston.git -b lineage-23.0 device/oneplus/aston --depth=1
git clone https://github.com/LineageOS/android_device_oneplus_sm8550-common.git -b lineage-23.0 device/oneplus/sm8550-common --depth=1
git clone https://github.com/gaurav-paul9/android_kernel_oneplus_sm8550.git -b lineage-23.0 kernel/oneplus/sm8550 --depth=1
git clone https://github.com/TheMuppets/proprietary_vendor_oneplus_aston.git -b lineage-23.0 vendor/oneplus/aston --depth=1
git clone https://github.com/TheMuppets/proprietary_vendor_oneplus_sm8550-common.git -b lineage-23.0 vendor/oneplus/sm8550-common --depth=1

# -------------------- Setup env & build --------------------
send_telegram "🧩 Setting up build environment..."
. build/envsetup.sh

send_telegram "🏗️ Starting build: ax -br ... (logging to out/error.log)"
mkdir -p out

# Run build and capture output to out/error.log (also visible in console)
ax -br -j$(nproc --all) 2>&1 | tee out/error.log

# -------------------- On success: upload ROM --------------------
BUILD_END_TS=$(date +%s)
DURATION_SEC=$((BUILD_END_TS - BUILD_START_TS))
HOURS=$((DURATION_SEC / 3600))
MINUTES=$(((DURATION_SEC % 3600) / 60))
SECONDS=$((DURATION_SEC % 60))
BUILD_DURATION_FMT=$(printf "%dh:%dm:%ds" ${HOURS} ${MINUTES} ${SECONDS})
UPLOAD_TIME_HUMAN=$(date '+%Y-%m-%d %H:%M')

# Find newest ROM zip starting with axion in the device output dir
ROM_PATH=$(find out/target/product/aston -type f -name "axion*.zip" -printf "%T@ %p\n" 2>/dev/null | sort -n | tail -n1 | awk '{for(i=2;i<=NF;i++){printf $i; if(i<NF) printf " "}}' || true)

if [ -z "${ROM_PATH:-}" ] || [ ! -f "${ROM_PATH:-}" ]; then
  send_telegram "⚠️ Build finished but no ROM zip found in out/target/product/aston/"
  exit 1
fi

ROM_NAME=$(basename "${ROM_PATH}")
FILE_SIZE=$(du -h "${ROM_PATH}" | cut -f1)
MD5_SUM=$(md5sum "${ROM_PATH}" | awk '{print $1}' || echo "N/A")

send_telegram "☁️ Uploading *${ROM_NAME}* (${FILE_SIZE}) to PixelDrain..."

# Upload to PixelDrain and parse id
PIXELDRAIN_JSON=$(curl -s -u ":${PIXELDRAIN_API_KEY}" -F "file=@${ROM_PATH}" https://pixeldrain.com/api/file || true)
FILE_ID=$(echo "${PIXELDRAIN_JSON}" | grep -o '"id":"[^"]*' | cut -d'"' -f4 || true)

if [ -z "${FILE_ID:-}" ]; then
  send_telegram "❌ PixelDrain upload failed. Response: ${PIXELDRAIN_JSON}"
  exit 1
fi

DL_LINK="https://pixeldrain.com/u/${FILE_ID}"

# Build success message (pretty)
read -r -d '' success_msg <<EOF || true
🎉 *AxionOS Upload Complete!* 
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 *Device:* ${DEVICE_NAME}
🕓 *Build Time:* \`${BUILD_DURATION_FMT}\`
📎 *Filename:* \`${ROM_NAME}\`
📦 *Size:* ${FILE_SIZE}
🔑 *MD5:* \`${MD5_SUM}\`
🗓️ *Uploaded:* ${UPLOAD_TIME_HUMAN}
🔗 *Download:* ${DL_LINK}
EOF

send_telegram "${success_msg}"

# Also send the build log as a document for convenience
if [ -f "out/error.log" ]; then
  send_telegram_document "out/error.log" "🧾 Full build log (successful build)"
fi

send_telegram "✅ *Build Completed Successfully!* 🎯"

exit 0
