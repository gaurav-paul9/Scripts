#!/bin/bash

# =================================================================
#                     Axion Build Script
# =================================================================
#
# Stop the script immediately if any command fails
set -e

# =======================
#   SETUP & PRE-CHECKS
# =======================

# Load environment variables from .env file
if [ -f .env ]; then
  set -o allexport
  source .env
  set +o allexport
else
  echo "Error: .env file not found! Create one with your secrets."
  exit 1
fi

# Check for required secrets
if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ] || [ -z "$PIXELDRAIN_API_KEY" ]; then
    echo "Error: One or more required variables are missing in your .env file."
    echo "Required: TG_BOT_TOKEN, TG_CHAT_ID, PIXELDRAIN_API_KEY"
    exit 1
fi

# Telegram notification function
send_telegram_message() {
    curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
        --data-urlencode "chat_id=$TG_CHAT_ID" \
        --data-urlencode "text=$1" \
        --data-urlencode "parse_mode=Markdown" > /dev/null
}

# Trap to send a notification on script failure
handle_exit() {
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        send_telegram_message "❌ *Build Failed!*

The script exited with a non-zero status code: \`$EXIT_CODE\`.
Please check the logs for the exact error."
    fi
}
trap handle_exit EXIT

# Send "Build Started" notification
send_telegram_message "🚀 *New Build Started for Aston!*

The build process has been initiated. I will notify you upon completion or failure."

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

echo "Performing selective cleanup of 'out' directory..."
rm -rf out/target/product/aston/system
rm -rf out/target/product/aston/product
echo "Cleanup finished."

# =======================
#   2. REPO INITIALIZATION & SYNC
# =======================
echo "Initializing infinity repository..."
repo init --no-repo-verify --git-lfs -u https://github.com/ProjectInfinity-X/manifest -b 16 -g default,-mips,-darwin,-notdefault


echo "Syncing sources..."
if [ -f "/opt/crave/resync.sh" ]; then
    /opt/crave/resync.sh
else
    repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j$(nproc --all)
fi


# =======================
#   4. CLONING ADDITIONAL REPOSITORIES
# =======================
echo "Cloning additional repositories..."
git clone https://github.com/gaurav-paul9/android_device_oneplus_aston.git -b inf device/oneplus/aston --depth=1
git clone https://github.com/gaurav-paul9/android_device_oneplus_sm8550-common.git -b lineage-23.0 device/oneplus/sm8550-common --depth=1
git clone https://github.com/gaurav-paul9/android_kernel_oneplus_sm8550.git -b newroot kernel/oneplus/sm8550 --depth=1
git clone https://github.com/LineageOS/android_kernel_oneplus_sm8550-modules.git -b lineage-23.0 kernel/oneplus/sm8550-modules --depth=1
git clone https://github.com/gaurav-paul9/android_kernel_oneplus_sm8550-devicetrees.git -b lineage-23.0 kernel/oneplus/sm8550-devicetrees --depth=1
git clone https://github.com/LineageOS/android_hardware_oplus.git -b lineage-23.0 hardware/oplus --depth=1
git clone https://github.com/inferno0230/hardware_dolby.git -b sixteen hardware/dolby --depth=1
git clone https://github.com/TheMuppets/proprietary_vendor_oneplus_aston.git -b lineage-23.0 vendor/oneplus/aston --depth=1
git clone https://gitlab.com/NoPrincessHere/proprietary_vendor_oneplus_sm8550-common.git -b sixteen vendor/oneplus/sm8550-common --depth=1
# =======================
#   6. BUILD THE ROM
# =======================
echo "Starting the build process..."
. build/envsetup.sh
lunch infinity_aston-user

echo "Running 'm installclean' for a safe build..."
m installclean

echo "Starting the main build..."
m bacon

send_telegram_message "✅ *Build Finished Successfully!*

Now preparing to upload the file..."


# =======================
#   7. UPLOAD THE BUILD
# =======================
echo "Starting the upload process..."

# === Stop Build Timer and Calculate Duration ===
BUILD_END_TIME=$(date +%s)
DURATION=$((BUILD_END_TIME - BUILD_START_TIME))
DURATION_FORMATTED=$(printf '%dh:%dm:%ds\n' $(($DURATION/3600)) $(($DURATION%3600/60)) $(($DURATION%60)))

OUTPUT_DIR="out/target/product/aston"
ZIP_FILE=$(find "$OUTPUT_DIR" -type f -iname "Project*.zip" -printf "%T@ %p\n" | sort -n | tail -n1 | cut -d' ' -f2-)

if [[ -f "$ZIP_FILE" ]]; then
  echo "Uploading $ZIP_FILE to Pixeldrain..."
  RESPONSE=$(curl -s -u ":$PIXELDRAIN_API_KEY" -X POST -F "file=@$ZIP_FILE" https://pixeldrain.com/api/file)
  FILE_ID=$(echo "$RESPONSE" | jq -r '.id')
  
  if [[ "$FILE_ID" != "null" && -n "$FILE_ID" ]]; then
    DOWNLOAD_URL="https://pixeldrain.com/u/$FILE_ID"
    FILE_NAME=$(basename "$ZIP_FILE")
    FILE_SIZE_BYTES=$(stat -c%s "$ZIP_FILE")
    FILE_SIZE_HUMAN=$(numfmt --to=iec --suffix=B "$FILE_SIZE_BYTES")
    UPLOAD_DATE=$(date +"%Y-%m-%d %H:%M")
    
    echo "Upload successful: $DOWNLOAD_URL"
    UPLOAD_MESSAGE="🎉 *AstonInfinity(Root) Upload Complete!*

*Build Time:* \`$DURATION_FORMATTED\`
📎 *Filename:* \`$FILE_NAME\`
📦 *Size:* $FILE_SIZE_HUMAN
🕓 *Uploaded:* $UPLOAD_DATE
🔗 [Download Link]($DOWNLOAD_URL)"
    send_telegram_message "$UPLOAD_MESSAGE"
  else
    echo "Upload failed. Pixeldrain response: $RESPONSE"
    send_telegram_message "❌ *Upload Failed!*

The build was successful, but the upload to Pixeldrain failed.
*Response:* \`$RESPONSE\`"
  fi
else
  echo "Error: No .zip file found in $OUTPUT_DIR"
  send_telegram_message "❌ *Upload Failed!*

The build seemed to complete, but no .zip file was found in \`$OUTPUT_DIR\`."
fi

echo "Script finished."

# Unset the trap explicitly for a clean successful exit
trap - EXIT
