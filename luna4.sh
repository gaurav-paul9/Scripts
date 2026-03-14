#!/bin/bash
# Script by Gaurav(Optimized for AI Studio & Telegram)
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
if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ] || [ -z "$PIXELDRAIN_API_KEY" ]; then
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

# Function to generate a progress bar
get_progress_bar() {
    local percent=$1
    local width=15
    local done=$((percent * width / 100))
    local left=$((width - done))
    local bar=$(printf "%${done}s" | tr ' ' '█')
    local empty=$(printf "%${left}s" | tr ' ' '░')
    echo "[$bar$empty]"
}

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
👤 *User:* \`$BUILD_USERNAME\`
💽 *Free Space:* \`$START_DISK\`
🕒 *Start Time:* \`$(date '+%I:%M %p')\`"

BUILD_START_TIME=$(date +%s)

# Clean
echo "🧹 Cleaning up..."
rm -rf out/target/product/aston/system \
       out/target/product/aston/product .repo/local_manifests
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
# (Your cloning block remains same)
rm -rf device/oneplus/aston device/oneplus/sm8550-common kernel/oneplus/sm8550 \
       kernel/oneplus/sm8550-modules kernel/oneplus/sm8550-devicetrees hardware/pixelworks/interfaces \
       hardware/oplus hardware/dolby vendor/oneplus/aston vendor/oneplus/sm8550-common

git clone https://github.com/gaurav-paul9/android_device_oneplus_aston.git -b luna device/oneplus/aston --depth=1
git clone https://github.com/gaurav-paul9/android_device_oneplus_sm8550-common.git -b lineage-23.2 device/oneplus/sm8550-common --depth=1
git clone https://github.com/OnePlus12R-development/android_kernel_oneplus_sm8550.git -b sixteen-qpr2 kernel/oneplus/sm8550 --depth=1
git clone https://github.com/OnePlus12R-development/android_kernel_oneplus_sm8550-modules.git -b sixteen-qpr2 kernel/oneplus/sm8550-modules --depth=1
git clone https://github.com/LineageOS/android_kernel_oneplus_sm8550-devicetrees.git -b lineage-23.2 kernel/oneplus/sm8550-devicetrees --depth=1
git clone https://github.com/LineageOS/android_hardware_oplus.git -b lineage-23.2 hardware/oplus --depth=1
git clone https://github.com/inferno0230/hardware_dolby.git -b sixteen-qpr2 hardware/dolby --depth=1
git clone https://github.com/TheMuppets/proprietary_vendor_oneplus_aston.git -b lineage-23.2 vendor/oneplus/aston --depth=1
git clone https://github.com/TheMuppets/proprietary_vendor_oneplus_sm8550-common.git -b lineage-23.2 vendor/oneplus/sm8550-common --depth=1
git clone https://github.com/LineageOS/android_hardware_pixelworks_interfaces -b lineage-23.2 --depth=1 hardware/pixelworks/interfaces

send_telegram_message "🎋 *Trees Cloned.*
🛠️ *Next:* Applying kernel patches..."

# --- 5.2 Kernel Fix ---
echo "🛠️ Applying videodev2.h fix..."
VIDEO_FILE="kernel/oneplus/sm8550/include/uapi/linux/videodev2.h"

if [ -f "$VIDEO_FILE" ]; then
    sed -i '60,62d' "$VIDEO_FILE"
    sed -i '62i #include <linux/time.h>' "$VIDEO_FILE"
    echo "✅ Kernel fix applied."
else
    echo "⚠️ Warning: $VIDEO_FILE not found!"
fi

# --- 5.3 Build with Live Monitor ---
echo "🏗️ Starting Build..."
. build/envsetup.sh
lunch lineage_aston-bp4a-userdebug

MSG_JSON=$(send_telegram_return_json "🏗️ *Compiling aston...*
Status: \`Initializing...\`")
MSG_ID=$(echo "$MSG_JSON" | jq -r '.result.message_id')

live_monitor() {
    local msg_id=$1
    local start_time=$(date +%s)
    local last_progress=""
    
    while true; do
        sleep 25 # Every 25s is safe for TG and feels frequent enough
        if [ -f "$BUILD_LOG" ]; then
            # Extract progress like [ 10% 123/1234]
            PROGRESS_LINE=$(tail -n 20 "$BUILD_LOG" | grep -o '\[.*% .*\]' | tail -n 1)
            
            # Extract current task (last line that contains the build target info)
            CURRENT_TASK=$(tail -n 5 "$BUILD_LOG" | grep "\] " | tail -n 1 | sed 's/.*\] //')
            
            if [[ ! -z "$PROGRESS_LINE" ]]; then
                # Avoid unnecessary edits if progress hasn't changed
                if [[ "$PROGRESS_LINE" == "$last_progress" ]]; then
                    continue
                fi
                last_progress="$PROGRESS_LINE"

                # Calculate Percentage and Bar
                PERCENT=$(echo "$PROGRESS_LINE" | grep -oE '[0-9]+%' | head -1 | tr -d '%')
                BAR=$(get_progress_bar "$PERCENT")
                
                # Calculate Duration
                NOW=$(date +%s)
                ELAPSED=$((NOW - start_time))
                RUNTIME=$(printf '%dh:%dm:%ds' $(($ELAPSED/3600)) $(($ELAPSED%3600/60)) $(($ELAPSED%60)))
                
                TEXT="🏗️ *Compiling aston...*
$BAR \`$PERCENT%\`

⏱️ *Elapsed:* \`$RUNTIME\`
📝 *Status:* \`$PROGRESS_LINE\`
🛠️ *Task:* \`$CURRENT_TASK\`

_Last Update: $(date +'%I:%M %p')_"
                
                edit_telegram_message "$msg_id" "$TEXT"
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
# (Remains largely the same, just made it look cleaner)
echo "📤 Build finished, processing artifacts..."
edit_telegram_message "$MSG_ID" "✅ *Build Finished!*
Processing & Uploading artifacts..."

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

    ZIP_URL=$(upload_to_pixeldrain "$ZIP_FILE")
    RECOVERY_URL=$(upload_to_pixeldrain "$RECOVERY_IMG")

    FINAL_MESSAGE="✅ *Build Success!* 🌟

⏱️ *Total Time:* \`$DURATION_FORMATTED\`
💾 *Size:* \`$SIZE_HUMAN\`
📦 *File:* \`$FILE_NAME\`
🛡️ *MD5:* \`$MD5SUM\`

📱 *Downloads:*"

    [[ "$ZIP_URL" =~ http ]] && FINAL_MESSAGE="$FINAL_MESSAGE
🔹 [ROM ZIP]($ZIP_URL)" || FINAL_MESSAGE="$FINAL_MESSAGE
🔹 ROM ZIP: Upload Failed ❌"

    [[ "$RECOVERY_URL" =~ http ]] && FINAL_MESSAGE="$FINAL_MESSAGE
🔹 [Recovery Image]($RECOVERY_URL)" || FINAL_MESSAGE="$FINAL_MESSAGE
🔹 Recovery: Not Found/Failed ❌"
    
    # OTA JSON Logic
    if [[ "$ZIP_URL" =~ http ]]; then
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
        [[ "$JSON_URL" =~ http ]] && FINAL_MESSAGE="$FINAL_MESSAGE
🔹 [OTA JSON]($JSON_URL)"
    fi

    FINAL_MESSAGE="$FINAL_MESSAGE

cc: @GauravPaul1"

    send_telegram_message "$FINAL_MESSAGE"
    send_telegram_file "$BUILD_LOG" "Full Build Log for $FILE_NAME"
    
else
    send_telegram_message "❌ *Build Failed (No ZIP Found)*
Process finished but no Lunaris ZIP was generated."
fi

trap - EXIT
echo "✅ Done."
