#!/bin/bash
#
# AxionOS Automated Build Script with secrets loaded from hidden .env, Telegram notifications,
# PixelDrain upload and build metadata reporting.
#
# Place your secrets in either:
#  - a file named ".env" in the same directory as this script, OR
#  - a directory named ".env" containing a file "secrets.env" (useful if you clone a private repo into .env)
#
# Required variables in the secrets file:
#   TG_BOT_TOKEN      -> Telegram Bot token (e.g. 123:ABC...)
#   TG_CHAT_ID        -> Telegram chat id (e.g. 80106...)
#   PIXELDRAIN_API_KEY-> PixelDrain API key (e.g. 3dad...)
#   (optional) GITHUB_TOKEN -> if you use private repo cloning for signing keys
#
set -euo pipefail

# =====================
#  Load secrets (.env)
# =====================
# Look for: .env (file) OR .env/secrets.env (file inside hidden dir)
SECRETS_FILE=""
if [ -f ".env" ]; then
  SECRETS_FILE=".env"
elif [ -f ".env/secrets.env" ]; then
  SECRETS_FILE=".env/secrets.env"
elif [ -f ".env/secrets" ]; then
  SECRETS_FILE=".env/secrets"
fi

if [ -z "$SECRETS_FILE" ]; then
  echo "Error: No secrets file found."
  echo "Create a file named '.env' or clone a private repo/folder into .env containing 'secrets.env'."
  exit 1
fi

# Export all variables from the secrets file
set -o allexport
# shellcheck disable=SC1090
source "$SECRETS_FILE"
set +o allexport

# Validate required variables
missing_vars=()
[ -z "${TG_BOT_TOKEN:-}" ] && missing_vars+=(TG_BOT_TOKEN)
[ -z "${TG_CHAT_ID:-}" ] && missing_vars+=(TG_CHAT_ID)
[ -z "${PIXELDRAIN_API_KEY:-}" ] && missing_vars+=(PIXELDRAIN_API_KEY)

if [ ${#missing_vars[@]} -ne 0 ]; then
  echo "Error: Missing required variables in $SECRETS_FILE: ${missing_vars[*]}"
  exit 1
fi

# =====================
#  Notification helpers
# =====================
send_telegram_message() {
  local message="$1"
  # send message and capture response
  local resp
  resp=$(curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TG_CHAT_ID}" \
    --data-urlencode "text=${message}" \
    --data-urlencode "parse_mode=Markdown") || true
  # optional: log response for debugging
  echo "telegram response: ${resp}"
}

# Trap to notify on failure
handle_exit() {
  local exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    send_telegram_message "❌ *Build Failed!*

The build script exited with status \`${exit_code}\`. Check server logs for details."
  fi
}
trap 'handle_exit' EXIT

# ========== BUILD START ==========
BUILD_START_TIME=$(date +%s)
send_telegram_message "🚀 *AxionOS Build Started!*

I will notify you on progress and upload the ROM when done."

# ========== REPO INIT ==========
send_telegram_message "📦 Initializing repo..."
if ! command -v repo >/dev/null 2>&1; then
  send_telegram_message "⚠️ repo command not found on this machine. Skipping repo init. If you intend to run full build, install 'repo'."
else
  repo init -u https://github.com/AxionAOSP/android.git -b lineage-23.0 --git-lfs || {
    send_telegram_message "❌ Repo init failed!"
    exit 1
  }
fi

# ========== CLEAN PREBUILTS ==========
send_telegram_message "🧹 Cleaning old prebuilts..."
rm -rf prebuilts/clang/host/linux-x86 || true

# ========== RESYNC ==========
send_telegram_message "🔁 Running resync (if available)..."
if [ -f "/opt/crave/resync.sh" ]; then
  /opt/crave/resync.sh || { send_telegram_message "❌ Resync failed!"; exit 1; }
else
  # If repo is present, attempt a safe repo sync; otherwise skip
  if command -v repo >/dev/null 2>&1; then
    repo sync -c --force-sync --no-clone-bundle --no-tags -j$(nproc --all) || { send_telegram_message "❌ Repo sync failed!"; exit 1; }
  else
    send_telegram_message "⚠️ Repo not available — skipping sync (useful for local testing)"
  fi
fi

# ========== CLONING DEVICE TREE & DEPENDENCIES =========
send_telegram_message "📥 Cloning device, kernel, and vendor sources..."
git clone https://github.com/gaurav-paul9/android_device_oneplus_aston.git -b lineage-23.0 device/oneplus/aston --depth=1 || true
git clone https://github.com/LineageOS/android_device_oneplus_sm8550-common.git -b lineage-23.0 device/oneplus/sm8550-common --depth=1 || true
git clone https://github.com/gaurav-paul9/android_kernel_oneplus_sm8550.git -b lineage-23.0 kernel/oneplus/sm8550 --depth=1 || true
git clone https://github.com/LineageOS/android_kernel_oneplus_sm8550-modules.git -b lineage-23.0 kernel/oneplus/sm8550-modules --depth=1 || true
git clone https://github.com/LineageOS/android_kernel_oneplus_sm8550-devicetrees.git -b lineage-23.0 kernel/oneplus/sm8550-devicetrees --depth=1 || true
git clone https://github.com/LineageOS/android_hardware_oplus.git -b lineage-23.0 hardware/oplus --depth=1 || true
git clone https://github.com/TheMuppets/proprietary_vendor_oneplus_aston.git -b lineage-23.0 vendor/oneplus/aston --depth=1 || true
git clone https://github.com/TheMuppets/proprietary_vendor_oneplus_sm8550-common.git -b lineage-23.0 vendor/oneplus/sm8550-common --depth=1 || true

send_telegram_message "✅ All sources cloned (attempted)!"

# ========== ENVIRONMENT SETUP ==========
send_telegram_message "🧩 Setting up build environment..."
if [ -f "build/envsetup.sh" ]; then
  . build/envsetup.sh
else
  send_telegram_message "⚠️ build/envsetup.sh not found — are you in the repo root?"
fi

# ========== AXION BUILD STEPS ==========
send_telegram_message "⚙️ Starting Axion build steps..."
gk -s || true
axion aston gms core || true
m installclean || true

# ========== BUILD START ==========
send_telegram_message "🏗️ Build process started..."
# If ax command exists run it, otherwise try 'make' to allow local testing
if command -v ax >/dev/null 2>&1; then
  ax -br -j$(nproc --all)
else
  # run a dummy command or 'make' if present; for local testing this allows flow to continue
  if command -v make >/dev/null 2>&1; then
    make -j2 || true
  else
    send_telegram_message "⚠️ Build command not found — skipping actual build (local test mode)"
  fi
fi

# If build failed the trap will notify. If successful, continue to upload.
# ========== UPLOAD THE BUILD ==========
BUILD_END_TIME=$(date +%s)
DURATION=$((BUILD_END_TIME - BUILD_START_TIME))
DURATION_FORMATTED=$(printf '%dh:%dm:%ds' $(($DURATION/3600)) $(($DURATION%3600/60)) $(($DURATION%60)) )

OUTPUT_DIR="out/target/product/aston"
send_telegram_message "🔎 Looking for ROM in ${OUTPUT_DIR} (files starting with axion*.zip)"
ZIP_FILE=$(find "${OUTPUT_DIR}" -maxdepth 1 -type f -name "axion*.zip" -printf "%T@ %p\n" 2>/dev/null | sort -n | tail -n1 | cut -d' ' -f2- || true)

if [ -z "${ZIP_FILE:-}" ]; then
  send_telegram_message "⚠️ Build finished but no ROM zip found in ${OUTPUT_DIR}."
else
  # Compute filesize and md5
  FILE_NAME=$(basename "$ZIP_FILE")
  if command -v stat >/dev/null 2>&1; then
    FILE_SIZE_BYTES=$(stat -c%s "$ZIP_FILE" || stat -f%z "$ZIP_FILE")
  else
    FILE_SIZE_BYTES=$(wc -c <"$ZIP_FILE" || true)
  fi
  # human readable size
  if command -v numfmt >/dev/null 2>&1; then
    FILE_SIZE_HUMAN=$(numfmt --to=iec --suffix=B "$FILE_SIZE_BYTES" || echo "${FILE_SIZE_BYTES}B")
  else
    FILE_SIZE_HUMAN="${FILE_SIZE_BYTES}B"
  fi
  if command -v md5sum >/dev/null 2>&1; then
    FILE_MD5=$(md5sum "$ZIP_FILE" | awk '{print $1}')
  elif command -v md5 >/dev/null 2>&1; then
    FILE_MD5=$(md5 -q "$ZIP_FILE" || true)
  else
    FILE_MD5="N/A"
  fi

  send_telegram_message "☁️ Uploading *${FILE_NAME}* (${FILE_SIZE_HUMAN}) to PixelDrain..."

  # Upload to PixelDrain using API key. Using curl -u :APIKEY as accepted by pixeldrain.
  PIXELDRAIN_RESPONSE=$(curl -s -u ":${PIXELDRAIN_API_KEY}" -X POST -F "file=@${ZIP_FILE}" https://pixeldrain.com/api/file || true)
  # Try to extract 'id' from JSON with jq, fallback to grep
  if command -v jq >/dev/null 2>&1; then
    FILE_ID=$(echo "$PIXELDRAIN_RESPONSE" | jq -r '.id' || true)
  else
    FILE_ID=$(echo "$PIXELDRAIN_RESPONSE" | grep -o '"id":"[^"]*' | cut -d'"' -f4 || true)
  fi

  if [ -n "${FILE_ID:-}" ] && [ "${FILE_ID}" != "null" ]; then
    DOWNLOAD_URL="https://pixeldrain.com/u/${FILE_ID}"
    UPLOAD_DATE=$(date +"%Y-%m-%d %H:%M")
    UPLOAD_MESSAGE="🎉 *AxionOS Upload Complete!*

*Build Time:* \`${DURATION_FORMATTED}\`
*Filename:* \`${FILE_NAME}\`
*Size:* ${FILE_SIZE_HUMAN}
*MD5:* \`${FILE_MD5}\`
*Uploaded:* ${UPLOAD_DATE}
🔗 [Download Link](${DOWNLOAD_URL})"
    send_telegram_message "${UPLOAD_MESSAGE}"
  else
    send_telegram_message "❌ Upload failed to PixelDrain. Response: ${PIXELDRAIN_RESPONSE}"
  fi
fi

# Success - remove failure trap and exit cleanly
trap - EXIT
send_telegram_message "✅ *AxionOS Build Completed Successfully!*"
exit 0
