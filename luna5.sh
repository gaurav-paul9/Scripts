#!/bin/bash
# Script by Dain using aistudio
set -e

# --- 1. System Configuration ---
echo "🕒 Setting System Timezone to India..."
sudo rm -f /etc/localtime
sudo ln -s /usr/share/zoneinfo/Asia/Kolkata /etc/localtime

BUILD_LOG="build.log"
ERROR_LOG="error_log.txt"

# --- 2. Load Environment ---
if [ -f .env ]; then
  set -o allexport
  source .env
  set +o allexport
else
  echo "❌ .env is missing!"
  exit 1
fi

# Validation
if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ] || [ -z "$PIXELDRAIN_API_KEY" ] || [ -z "$GH_TOKEN" ]; then
    echo "❌ Missing variables in .env"
    exit 1
fi

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
    mkdir -p ~/bin
    curl -L -o ~/bin/jq https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux64
    chmod +x ~/bin/jq
    export PATH=$HOME/bin:$PATH
fi

# --- 3. Helper Functions ---
send_telegram_message() {
    local text="$1"
    curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
        --data-urlencode "chat_id=$TG_CHAT_ID" \
        --data-urlencode "text=$text" \
        --data-urlencode "parse_mode=Markdown" \
        --data-urlencode "disable_web_page_preview=true" > /dev/null
}

send_telegram_return_json() {
    local text="$1"
    curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/sendMessage" \
        --data-urlencode "chat_id=$TG_CHAT_ID" \
        --data-urlencode "text=$text" \
        --data-urlencode "parse_mode=Markdown" \
        --data-urlencode "disable_web_page_preview=true"
}

edit_telegram_message() {
    local msg_id=$1
    local text=$2
    curl -s -X POST "https://api.telegram.org/bot$TG_BOT_TOKEN/editMessageText" \
        --data-urlencode "chat_id=$TG_CHAT_ID" \
        --data-urlencode "message_id=$msg_id" \
        --data-urlencode "text=$text" \
        --data-urlencode "parse_mode=Markdown" \
        --data-urlencode "disable_web_page_preview=true" > /dev/null
}

send_telegram_file() {
    local file_path="$1"
    local caption="$2"
    curl -s -F "chat_id=$TG_CHAT_ID" \
         -F "document=@$file_path" \
         -F "caption=$caption" \
         "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" > /dev/null
}

upload_to_pixeldrain() {
    local file_path=$1
    if [ -f "$file_path" ]; then
        RESPONSE=$(curl -sS -u ":$PIXELDRAIN_API_KEY" -F "file=@$file_path" https://pixeldrain.com/api/file)
        FILE_ID=$(echo "$RESPONSE" | jq -r '.id // empty')
        if [[ -n "$FILE_ID" && "$FILE_ID" != "null" ]]; then
            echo "https://pixeldrain.com/u/$FILE_ID"
        else
            echo "error"
        fi
    else
        echo "missing"
    fi
}

handle_exit() {
    code=$?
    if [ ! -z "$MONITOR_PID" ]; then kill $MONITOR_PID 2>/dev/null; fi
    
    if [ $code -ne 0 ]; then
        if [ -f "$BUILD_LOG" ]; then
            tail -n 200 "$BUILD_LOG" > "$ERROR_LOG"
            send_telegram_message "🚨 *Build Failed!* ❌
Exit code: \`$code\`
Check the log snippet below."
            send_telegram_file "$ERROR_LOG" "Error Log Snippet"
        else
            send_telegram_message "🚨 *Build Failed!* (No Log found)"
        fi
    fi
}
trap handle_exit EXIT

# --- 4. Build Environment Setup ---
export BUILD_USERNAME=gaurav
export BUILD_HOSTNAME=crave
export KBUILD_BUILD_USER=gaurav
export KBUILD_BUILD_HOST=crave
export USER=gaurav
export HOSTNAME=crave

# --- 5. Script Start ---
START_DISK=$(df -h . | awk 'NR==2 {print $4}')

send_telegram_message "🚀 *Build Started for Aston*
User: \`$BUILD_USERNAME\`
Free Space: \`$START_DISK\`
Time: \`$(date '+%I:%M %p')\`"

BUILD_START_TIME=$(date +%s)

# Clean
echo "🧹 Cleaning up..."
rm -rf .repo/local_manifests
rm -f "$BUILD_LOG" "$ERROR_LOG" ota.json

# Repo Init & Sync
echo "🔄 Initializing Repo..."
repo init -u https://github.com/Lunaris-AOSP/android -b 16.2 --git-lfs

echo "⬇️ Syncing..."
SYNC_START=$(date +%s)
if [ -f "/opt/crave/resync.sh" ]; then
    /opt/crave/resync.sh
else
    repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags
fi
SYNC_END=$(date +%s)
SYNC_DIFF=$((SYNC_END - SYNC_START))
send_telegram_message "✅ *Sync Completed* ($((SYNC_DIFF / 60)) mins).
🌿 *Next:* Cloning device trees..."

# --- 5.1 Clone Device Trees ---
echo "🌿 Cloning Device Trees..."
rm -rf device/oneplus/aston device/oneplus/sm8550-common kernel/oneplus/sm8550 packages/apps/Updater \
       kernel/oneplus/sm8550-modules kernel/oneplus/sm8550-devicetrees hardware/pixelworks/interfaces \
       hardware/oplus hardware/dolby vendor/oneplus/aston vendor/oneplus/sm8550-common vendor/lunaris-priv/keys

git clone https://github.com/gaurav-paul9/android_device_oneplus_aston.git -b lineage-23.2 device/oneplus/aston --depth=1
git clone https://github.com/gaurav-paul9/android_device_oneplus_sm8550-common.git -b los device/oneplus/sm8550-common --depth=1
git clone https://github.com/LineageOS/android_kernel_oneplus_sm8550.git -b lineage-23.2 kernel/oneplus/sm8550 --depth=1
git clone https://github.com/LineageOS/android_kernel_oneplus_sm8550-modules.git -b lineage-23.2 kernel/oneplus/sm8550-modules --depth=1
git clone https://github.com/LineageOS/android_kernel_oneplus_sm8550-devicetrees.git -b lineage-23.2 kernel/oneplus/sm8550-devicetrees --depth=1
git clone https://github.com/LineageOS/android_hardware_oplus.git -b lineage-23.2 hardware/oplus --depth=1
git clone https://github.com/Pong-Development/hardware_dolby.git -b 16 hardware/dolby --depth=1
git clone https://github.com/TheMuppets/proprietary_vendor_oneplus_aston.git -b lineage-23.2 vendor/oneplus/aston --depth=1
git clone https://github.com/TheMuppets/proprietary_vendor_oneplus_sm8550-common.git -b lineage-23.2 vendor/oneplus/sm8550-common --depth=1
git clone https://github.com/LineageOS/android_hardware_pixelworks_interfaces.git -b lineage-23.2 --depth=1 hardware/pixelworks/interfaces
git clone https://github.com/gaurav-paul9/packages_apps_Updater.git -b 16.2 packages/apps/Updater
git clone https://gaurav-paul9:${GH_TOKEN}@github.com/gaurav-paul9/android_vendor_lineage-priv_keys -b luna vendor/lunaris-priv/keys

send_telegram_message "🎋 *Trees Cloned.*
🛠️ *Next:* Applying kernel patches..."

# --- 5.2 Kernel Fix (videodev2.h) ---
echo "🛠️ Applying videodev2.h fix..."
VIDEO_FILE="kernel/oneplus/sm8550/include/uapi/linux/videodev2.h"

if [ -f "$VIDEO_FILE" ]; then
    sed -i '60,62d' "$VIDEO_FILE"
    sed -i '62i #include <linux/time.h>' "$VIDEO_FILE"
    echo "✅ Kernel fix applied."
else
    echo "⚠️ Warning: $VIDEO_FILE not found!"
    send_telegram_message "⚠️ *Warning:* videodev2.h not found. Patch skipped."
fi

sed -i '$a \\nallow hal_bluetooth_default vendor_ramdump_vendor_data_file:dir rw_dir_perms;\nallow hal_bluetooth_default vendor_ramdump_vendor_data_file:file { create getattr w_file_perms };' hardware/oplus/sepolicy/qti/vendor/hal_bluetooth_default.te

# --- 5.3 Build with Live Monitor ---
echo "🏗️ Starting Build..."
. build/envsetup.sh
lunch lineage_aston-bp4a-user

MSG_JSON=$(send_telegram_return_json "🏗️ *Compiling aston...*
Status: \`Initializing...\`")
MSG_ID=$(echo "$MSG_JSON" | jq -r '.result.message_id')

live_monitor() {
    local msg_id=$1
    while true; do
        sleep 60
        if [ -f "$BUILD_LOG" ]; then
            PROGRESS=$(tail -n 5 "$BUILD_LOG" | grep -o '\[.*\]' | tail -n 1)
            if [[ ! -z "$PROGRESS" ]]; then
                edit_telegram_message "$msg_id" "🏗️ *Compiling aston...*
Status: \`$PROGRESS\`
_Last Update: $(date +'%I:%M %p')_"
            fi
        fi
    done
}

live_monitor "$MSG_ID" & 
MONITOR_PID=$!

set -o pipefail
m bacon 2>&1 | tee "$BUILD_LOG"

kill $MONITOR_PID 2>/dev/null
MONITOR_PID=""

# --- 6. Post-Build & Upload ---
echo "📤 Build finished, processing artifacts..."
edit_telegram_message "$MSG_ID" "✅ *Build Finished!*
Processing & Uploading..."

BUILD_END_TIME=$(date +%s)
DURATION=$((BUILD_END_TIME - BUILD_START_TIME))
DURATION_FORMATTED=$(printf '%dh:%dm:%ds' $(($DURATION/3600)) $(($DURATION%3600/60)) $(($DURATION%60)))

OUTPUT_DIR="out/target/product/aston"
ZIP_FILE=$(find "$OUTPUT_DIR" -type f -name "Lunaris*.zip" -mmin -260 -printf "%T@ %p\n" | sort -n | tail -n1 | cut -d' ' -f2-)
RECOVERY_IMG=$(find "$OUTPUT_DIR" -type f -name "recovery.img" -mmin -260 | head -n 1)

if [[ -f "$ZIP_FILE" ]]; then
    MD5SUM=$(md5sum "$ZIP_FILE" | awk '{print $1}')
    FILE_NAME=$(basename "$ZIP_FILE")
    SIZE=$(stat -c%s "$ZIP_FILE")
    SIZE_HUMAN=$(numfmt --to=iec --suffix=B "$SIZE")

    echo "Uploading ZIP to Pixeldrain..."
    ZIP_URL=$(upload_to_pixeldrain "$ZIP_FILE")
    
    echo "Uploading Recovery to Pixeldrain..."
    RECOVERY_URL=$(upload_to_pixeldrain "$RECOVERY_IMG")

    # Construct Success Message
    FINAL_MESSAGE="✅ *Build Success!* 🌟

⏱️ *Time:* \`$DURATION_FORMATTED\`
💾 *Size:* \`$SIZE_HUMAN\`
📦 *File:* \`$FILE_NAME\`
🛡️ *MD5:* \`$MD5SUM\`

📱 *Downloads:*"

    if [[ "$ZIP_URL" == "error" || "$ZIP_URL" == "missing" ]]; then
        FINAL_MESSAGE="$FINAL_MESSAGE
🔹 ROM ZIP: Upload Failed ❌"
    else
        FINAL_MESSAGE="$FINAL_MESSAGE
🔹 [ROM ZIP]($ZIP_URL)"
    fi

    if [[ "$RECOVERY_URL" == "error" || "$RECOVERY_URL" == "missing" ]]; then
        FINAL_MESSAGE="$FINAL_MESSAGE
🔹 Recovery Image: Upload Failed or Not Found ❌"
    else
        FINAL_MESSAGE="$FINAL_MESSAGE
🔹 [Recovery Image]($RECOVERY_URL)"
    fi
    
    # OTA JSON
    if [[ "$ZIP_URL" != "error" && "$ZIP_URL" != "missing" ]]; then
        TIMESTAMP=$(date +%s)
        cat <<EOF > ota.json
{
  "response": [
    {
      "datetime": $TIMESTAMP,
      "filename": "$FILE_NAME",
      "id": "$MD5SUM",
      "romtype": "unofficial",
      "size": $SIZE,
      "url": "$ZIP_URL",
      "version": "15.0"
    }
  ]
}
EOF
        JSON_URL=$(upload_to_pixeldrain "ota.json")
        if [[ "$JSON_URL" == "error" || "$JSON_URL" == "missing" ]]; then
            FINAL_MESSAGE="$FINAL_MESSAGE
🔹 OTA JSON: Upload Failed ❌"
        else
            FINAL_MESSAGE="$FINAL_MESSAGE
🔹 [OTA JSON]($JSON_URL)"
        fi
    fi

    FINAL_MESSAGE="$FINAL_MESSAGE

cc: @GauravPaul1"

    # Send Success Details
    send_telegram_message "$FINAL_MESSAGE"
    
    # Send FULL Build Log as requested
    echo "Sending Full Build Log to Telegram..."
    send_telegram_file "$BUILD_LOG" "Full Build Log for $FILE_NAME"
    
else
    send_telegram_message "❌ *Build Failed (No ZIP Found)*
The build process completed, but the Lunaris ZIP was not found."
fi

trap - EXIT
echo "✅ Done."
