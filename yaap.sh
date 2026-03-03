#!/bin/bash
# YAAP
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
    if [ -f "$file_path" ]; then
        curl -s -F "chat_id=$TG_CHAT_ID" \
             -F "document=@$file_path" \
             -F "caption=$caption" \
             "https://api.telegram.org/bot$TG_BOT_TOKEN/sendDocument" > /dev/null
    fi
}

upload_to_pixeldrain() {
    local file_path=$1
    if [ -f "$file_path" ]; then
        RESPONSE=$(curl -sS -u ":$PIXELDRAIN_API_KEY" -F "file=@$file_path" https://pixeldrain.com/api/file)
        FILE_ID=$(echo "$RESPONSE" | jq -r '.id // empty')
        [[ -n "$FILE_ID" && "$FILE_ID" != "null" ]] && echo "https://pixeldrain.com/u/$FILE_ID" || echo "error"
    else
        echo "missing"
    fi
}

# --- 4. Enhanced Error Handling & Monitor ---
handle_exit() {
    code=$?
    if [ ! -z "$MONITOR_PID" ]; then kill $MONITOR_PID 2>/dev/null; fi
    
    if [ $code -ne 0 ]; then
        echo "🚨 Build Failed with code $code. Collecting logs..."
        
        # 1. Create a snippet from the end of the main build log
        if [ -f "$BUILD_LOG" ]; then
            tail -n 500 "$BUILD_LOG" > "$ERROR_LOG"
            send_telegram_message "🚨 *YAAP Build Failed!* ❌
Exit Code: \`$code\`
Check the attached log files for errors."
            send_telegram_file "$ERROR_LOG" "Snippet from build.log"
        fi

        # 2. Search for the latest internal Android error logs in 'out/'
        # These often contain the ACTUAL reason for failure (Soong/Ninja errors)
        SEARCH_LOGS=$(find out -maxdepth 4 -name "soong.log" -o -name "verbose.log.gz" -o -name "error" -mmin -20 2>/dev/null | sort -r | head -n 2)
        
        for logfile in $SEARCH_LOGS; do
            send_telegram_file "$logfile" "System Error Log: $(basename $logfile)"
        done
    fi
}
trap handle_exit EXIT

live_monitor() {
    local msg_id=$1
    local last_progress=""
    while true; do
        sleep 60
        if [ -f "$BUILD_LOG" ]; then
            # Catch percentage OR the actual activity text
            PROGRESS=$(tail -n 20 "$BUILD_LOG" | grep -o '\[.*%\]' | tail -n 1 || tail -n 20 "$BUILD_LOG" | grep -o '\[.*\/.*\]' | tail -n 1)
            
            # If no progress bracket found, just show the last line of action
            if [[ -z "$PROGRESS" ]]; then
                PROGRESS=$(tail -n 1 "$BUILD_LOG" | cut -c1-60)
            fi

            if [[ "$PROGRESS" != "$last_progress" && ! -z "$PROGRESS" ]]; then
                edit_telegram_message "$msg_id" "🏗️ *Compiling YAAP aston...*
📍 *Status:* \`$PROGRESS\`
🕒 *Update:* \`$(date '+%I:%M %p')\`"
                last_progress="$PROGRESS"
            fi
        fi
    done
}

# --- 5. Build Start ---
export BUILD_USERNAME=gaurav
export BUILD_HOSTNAME=crave

send_telegram_message "🚀 *YAAP Build Started for Aston*
Time: \`$(date '+%I:%M %p')\`"

# Cleanup
echo "🧹 Cleaning..."
rm -rf out/target/product/aston/system out/target/product/aston/product .repo "$BUILD_LOG" "$ERROR_LOG"

# Repo Init (YAAP)
repo init -u https://github.com/yaap/manifest.git -b sixteen --git-lfs
/opt/crave/resync.sh

# --- 5.1 Clone Trees ---
echo "🌿 Cloning Trees..."
rm -rf device/oneplus/aston device/oneplus/sm8550-common kernel/oneplus/sm8550 kernel/oneplus/sm8550-modules kernel/oneplus/sm8550-devicetrees hardware/pixelworks/interfaces hardware/oplus hardware/dolby vendor/oneplus/aston vendor/oneplus/sm8550-common

git clone https://gitlab.com/gauravpaul9/android_device_oneplus_aston_yaap.git -b lineage-23.2 device/oneplus/aston --depth=1
git clone https://gitlab.com/gauravpaul9/android_device_oneplus_sm8550-common_yaap.git -b lineage-23.2 device/oneplus/sm8550-common --depth=1
git clone https://github.com/OnePlus12R-development/android_kernel_oneplus_sm8550.git -b sixteen-qpr2 kernel/oneplus/sm8550 --depth=1
git clone https://github.com/OnePlus12R-development/android_kernel_oneplus_sm8550-modules.git -b sixteen-qpr2 kernel/oneplus/sm8550-modules --depth=1
git clone https://github.com/LineageOS/android_kernel_oneplus_sm8550-devicetrees.git -b lineage-23.2 kernel/oneplus/sm8550-devicetrees --depth=1
git clone https://gitlab.com/gauravpaul9/hardware_oplus.git -b lineage-23.2 hardware/oplus --depth=1
git clone https://github.com/TheMuppets/proprietary_vendor_oneplus_aston.git -b lineage-23.2 vendor/oneplus/aston --depth=1
git clone https://gitlab.com/gauravpaul9/proprietary_vendor_oneplus_sm8550-common_yaap.git -b yaap vendor/oneplus/sm8550-common --depth=1
git clone https://github.com/LineageOS/android_hardware_pixelworks_interfaces -b lineage-23.2 --depth=1 hardware/pixelworks/interfaces
git clone https://github.com/inferno0230/hardware_dolby.git -b sixteen-qpr2 hardware/dolby --depth=1

# Audio/Sepolicy
rm -rf hardware/qcom-caf/sm8550/audio/primary-hal hardware/qcom-caf/sm8550/audio/agm hardware/qcom-caf/sm8550/audio/graphservices hardware/qcom-caf/sm8550/audio/pal hardware/qcom-caf/common device/qcom/sepolicy_vndr/sm8550
git clone https://github.com/LineageOS/android_hardware_qcom_audio-ar -b lineage-23.2-caf-sm8550 hardware/qcom-caf/sm8550/audio/primary-hal
git clone https://github.com/LineageOS/android_vendor_qcom_opensource_agm -b lineage-23.2-caf-sm8550 hardware/qcom-caf/sm8550/audio/agm
git clone https://github.com/LineageOS/android_vendor_qcom_opensource_audioreach-graphservices -b lineage-23.2-caf-sm8550 hardware/qcom-caf/sm8550/audio/graphservices
git clone https://github.com/LineageOS/android_vendor_qcom_opensource_arpal-lx -b lineage-23.2-caf-sm8550 hardware/qcom-caf/sm8550/audio/pal
git clone https://github.com/LineageOS/android_hardware_qcom-caf_common.git -b lineage-23.2 hardware/qcom-caf/common
git clone https://github.com/LineageOS/android_device_qcom_sepolicy_vndr -b lineage-23.2-caf-sm8550 device/qcom/sepolicy_vndr/sm8550

# Patch
sed -i 's/name_hash = hex(hash((self.plat_id, self.board_id, self.pmic_id)))/name_hash = hex(hash(self))/' vendor/yaap/build/tools/merge_dtbs.py

# --- 5.2 Build ---
. build/envsetup.sh
lunch yaap_aston-userdebug

MSG_JSON=$(send_telegram_return_json "🏗️ *Compiling YAAP aston...*
Status: \`Initializing...\`")
MSG_ID=$(echo "$MSG_JSON" | jq -r '.result.message_id')

live_monitor "$MSG_ID" & 
MONITOR_PID=$!

set -o pipefail
m yaap 2>&1 | tee "$BUILD_LOG"

kill $MONITOR_PID 2>/dev/null
MONITOR_PID=""

# --- 6. Success & Upload ---
OUTPUT_DIR="out/target/product/aston"
ZIP_FILE=$(find "$OUTPUT_DIR" -type f -name "yaap*.zip" -o -name "YAAP*.zip" -mmin -260 | head -n 1)

if [[ -f "$ZIP_FILE" ]]; then
    ZIP_URL=$(upload_to_pixeldrain "$ZIP_FILE")
    send_telegram_message "✅ *YAAP Build Success!*
📦 [Download ROM]($ZIP_URL)"
    send_telegram_file "$BUILD_LOG" "Full Build Log"
else
    send_telegram_message "❌ *Build Finished (No ZIP Found)*"
    # Trigger log send manually if zip is missing even though m yaap finished
    handle_exit
fi

trap - EXIT
echo "✅ Done."
