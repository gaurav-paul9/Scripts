#!/bin/bash
# =========================================================
#  AxionOS Dual Build Automation v9 (Final Production)
#  Clean Build + Rooted Build (KernelSU) with:
#  ✅ Telegram Live Progress (every 2 min)
#  ✅ PixelDrain Uploads
#  ✅ Duration Tracking
#  ✅ Auto Error Alerts
# =========================================================

set -eEuo pipefail
trap 'send_raw "💥 *Build Failed!* at line $LINENO. Check logs in out directory."' ERR

# --- Load secrets from .env ---
set -o allexport
source .env/secrets.env
set +o allexport

# --- Helper functions ---
send_raw() {
  curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TG_CHAT_ID}" \
    -d parse_mode="Markdown" \
    --data-urlencode "text=$1"
}

edit_raw() {
  curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/editMessageText" \
    -d chat_id="${TG_CHAT_ID}" \
    -d message_id="$1" \
    -d parse_mode="Markdown" \
    --data-urlencode "text=$2"
}

upload_rom() {
  local file="$1"
  local response
  response=$(curl -s -u ":${PIXELDRAIN_API_KEY}" -F "file=@${file}" https://pixeldrain.com/api/file || echo "")
  local id
  id=$(echo "$response" | grep -oE '"id":"[^"]+"' | head -n1 | cut -d'"' -f4 || echo "")
  if [ -z "$id" ]; then
    echo "UPLOAD_ERROR"
  else
    echo "https://pixeldrain.com/u/${id}"
  fi
}

elapsed() {
  printf "%02dh:%02dm:%02ds" $(( $1/3600 )) $(( ($1/60)%60 )) $(( $1%60 ))
}

# --- Start Telegram notification ---
msg=$(send_raw "⚙️ *AxionOS Build Started* for *Aston* ⚙️
━━━━━━━━━━━━━━━━━━━━━━
👤 *User:* Gaurav Paul
🧱 *Mode:* Dual Build (Clean + Root)
⏳ *Elapsed:* 0s

_Build initialization in progress..._ 💨")

MSG_ID=$(echo "$msg" | grep -o '"message_id":[0-9]\+' | cut -d: -f2 | head -n1 || echo "")
USE_EDIT=1
[ -z "$MSG_ID" ] && USE_EDIT=0

# --- Progress updater ---
monitor_progress() {
  local pid="$1" stage="$2"
  local start=$(date +%s)
  while kill -0 "$pid" 2>/dev/null; do
    sleep 120
    local e=$(( $(date +%s) - start ))
    local p=$(( (e / 45) % 100 )) # pseudo progress percentage
    ((p > 99)) && p=99
    local filled=$((p/5))
    local bar="$(printf '█%.0s' $(seq 1 $filled); printf '░%.0s' $(seq $((filled+1)) 20))"
    local text="⚙️ *AxionOS Build In Progress*  
━━━━━━━━━━━━━━━━━━━━━━  
🏗️ *Stage:* ${stage}  
📊 *Progress:* [${bar}] ${p}%  
⏳ *Elapsed:* $(elapsed $e)  

_Compiling beautifully... hang tight!_ ⚡"
    if [ "$USE_EDIT" -eq 1 ]; then
      edit_raw "$MSG_ID" "$text" >/dev/null 2>&1 || send_raw "$text" >/dev/null 2>&1
    else
      send_raw "$text" >/dev/null 2>&1
    fi
  done
}

# =========================================================
# 🧼 CLEAN BUILD
# =========================================================
send_raw "🧼 *Starting Clean Build...* 🚀"

repo init -u https://github.com/AxionAOSP/android.git -b lineage-23.0 --git-lfs
repo sync -j$(nproc --all)
. build/envsetup.sh && lunch axion_aston-user

BUILD_START_CLEAN=$(date +%s)
make -j$(nproc --all) otapackage 2>&1 | tee out/error_clean.log & BUILD_PID=$!
monitor_progress "$BUILD_PID" "Clean Build" &
wait $BUILD_PID
CLEAN_TIME=$(( $(date +%s) - BUILD_START_CLEAN ))

ROM1=$(find out/target/product/aston -type f -name "axion*.zip" | tail -n1)
L1=$(upload_rom "$ROM1")
S1=$(du -h "$ROM1" | cut -f1)

if [ "$L1" = "UPLOAD_ERROR" ]; then
  send_raw "✅ *Clean Build Complete!*  
━━━━━━━━━━━━━━━━━━━━━━  
❌ Upload Failed  
🕓 Duration: $(elapsed $CLEAN_TIME)"
else
  send_raw "✅ *Clean Build Complete!*  
━━━━━━━━━━━━━━━━━━━━━━  
📎 *Filename:* $(basename "$ROM1")  
📦 *Size:* ${S1}  
🔗 [PixelDrain Link](${L1})  
🕓 Duration: $(elapsed $CLEAN_TIME)"
fi

# =========================================================
# 🔑 ROOTED BUILD (KernelSU)
# =========================================================
send_raw "🔑 *Starting Rooted Build (KernelSU)* 🚀"
rm -rf kernel/oneplus/sm8550
git clone https://github.com/gaurav-paul9/android_kernel_oneplus_sm8550.git -b newroot kernel/oneplus/sm8550 --depth=1

BUILD_START_ROOT=$(date +%s)
make -j$(nproc --all) otapackage 2>&1 | tee out/error_root.log & BUILD_PID=$!
monitor_progress "$BUILD_PID" "Rooted Build - KernelSU" &
wait $BUILD_PID
ROOT_TIME=$(( $(date +%s) - BUILD_START_ROOT ))
TOTAL_TIME=$(( CLEAN_TIME + ROOT_TIME ))

ROM2=$(find out/target/product/aston -type f -name "axion*.zip" | tail -n1)
L2=$(upload_rom "$ROM2")
S2=$(du -h "$ROM2" | cut -f1)

if [ "$L2" = "UPLOAD_ERROR" ]; then
  send_raw "✅ *Rooted Build (KernelSU) Complete!*  
━━━━━━━━━━━━━━━━━━━━━━  
❌ Upload Failed  
⏳ Root Build Duration: $(elapsed $ROOT_TIME)
🕓 Total Duration: $(elapsed $TOTAL_TIME)"
else
  send_raw "✅ *Rooted Build (KernelSU) Complete!*  
━━━━━━━━━━━━━━━━━━━━━━  
📎 *Filename:* $(basename "$ROM2")  
📦 *Size:* ${S2}  
🔗 [PixelDrain Link](${L2})  
⏳ Root Build Duration: $(elapsed $ROOT_TIME)
🕓 Total Duration: $(elapsed $TOTAL_TIME)"
fi

# =========================================================
# 🎉 FINAL SUMMARY
# =========================================================
send_raw "🎉 *AxionOS Dual Build Cycle Completed!*  
━━━━━━━━━━━━━━━━━━━━━━
🧼 *Clean Build:* [PixelDrain Link](${L1})  
🔑 *Rooted Build:* [PixelDrain Link](${L2})  

🕓 *Clean Duration:* $(elapsed $CLEAN_TIME)  
⏳ *Root Duration:* $(elapsed $ROOT_TIME)  
🕓 *Total Duration:* $(elapsed $TOTAL_TIME)  

_Ready to flash and enjoy!_ ⚡"