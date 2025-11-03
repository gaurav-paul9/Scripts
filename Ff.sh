# =========================================================
#   🌌  AxionOS v13 Build Automation Script
#   🧠  Created by: Gaurav Paul
#   ⚙️  Features: Telegram Notifications + PixelDrain Uploads
#   📦  Dual Build: Clean + KernelSU Rooted
#   🔐  Auto Key Generation | Portable .env support
#   🕓  Version: v13 Final Production
# =========================================================

#!/bin/bash
set -eEuo pipefail
trap 'send_raw "💥 *Build Failed!* at line $LINENO. Check logs in out directory."' ERR

# --- Load secrets from .env (portable) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env/secrets.env" ]; then
  source "$SCRIPT_DIR/.env/secrets.env"
elif [ -f "./.env/secrets.env" ]; then
  source "./.env/secrets.env"
else
  echo "❌ .env/secrets.env not found! Exiting."
  exit 1
fi

# --- Telegram Functions ---
send_raw() { curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" -d chat_id="${TG_CHAT_ID}" -d parse_mode="Markdown" --data-urlencode "text=$1"; }
edit_raw() { curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/editMessageText" -d chat_id="${TG_CHAT_ID}" -d message_id="$1" -d parse_mode="Markdown" --data-urlencode "text=$2"; }

upload_rom() {
  local file="$1"
  local response=$(curl -s -u ":${PIXELDRAIN_API_KEY}" -F "file=@${file}" https://pixeldrain.com/api/file || echo "")
  local id=$(echo "$response" | grep -oE '"id":"[^"]+"' | head -n1 | cut -d'"' -f4 || echo "")
  [ -z "$id" ] && echo "UPLOAD_ERROR" || echo "https://pixeldrain.com/u/${id}"
}
elapsed() { printf "%02dh:%02dm:%02ds" $(( $1/3600 )) $(( ($1/60)%60 )) $(( $1%60 )); }

# --- Start Telegram notification ---
msg=$(send_raw "⚙️ *AxionOS Build Started* for *Aston* ⚙️
━━━━━━━━━━━━━━━━━━━━━━
👤 *User:* Gaurav Paul
🧱 *Mode:* Dual Build (Clean + Root)
_Preparing environment..._ 💨")
MSG_ID=$(echo "$msg" | grep -o '"message_id":[0-9]\+' | cut -d: -f2 | head -n1 || echo "")
USE_EDIT=1; [ -z "$MSG_ID" ] && USE_EDIT=0

monitor_progress() {
  local pid="$1" stage="$2" start=$(date +%s)
  while kill -0 "$pid" 2>/dev/null; do
    sleep 120; local e=$(( $(date +%s) - start ))
    local p=$(( (e / 45) % 100 )); ((p > 99)) && p=99
    local filled=$((p/5))
    local bar="$(printf '█%.0s' $(seq 1 $filled); printf '░%.0s' $(seq $((filled+1)) 20))"
    local text="⚙️ *AxionOS Build In Progress*  
━━━━━━━━━━━━━━━━━━━━━━  
🏗️ *Stage:* ${stage}  
📊 *Progress:* [${bar}] ${p}%  
⏳ *Elapsed:* $(elapsed $e)"
    if [ "$USE_EDIT" -eq 1 ]; then edit_raw "$MSG_ID" "$text" >/dev/null 2>&1 || send_raw "$text" >/dev/null 2>&1; else send_raw "$text" >/dev/null 2>&1; fi
  done
}

# 🧹 Cleanup
send_raw "🧹 *Cleaning old build directories and conflicts...* ♻️"
rm -rf device/oneplus/aston device/oneplus/sm8550-common kernel/oneplus/sm8550 kernel/oneplus/sm8550-modules kernel/oneplus/sm8550-devicetrees hardware/oplus hardware/dolby vendor/oneplus/aston vendor/oneplus/sm8550-common out/target/product/aston/system out/target/product/aston/product || true
send_raw "✅ *Cleanup Complete!* 🧼"

# 🧼 Clean Build
send_raw "🧼 *Starting Clean Build...* 🚀"
repo init -u https://github.com/AxionAOSP/android.git -b lineage-23.0 --git-lfs
rm -rf prebuilts/clang/host/linux-x86
bash /opt/crave/resync.sh

# 🔗 Clone repos
send_raw "📦 *Cloning device, kernel, and vendor repositories...*"
git clone https://github.com/gaurav-paul9/android_device_oneplus_aston.git -b lineage-23.0 device/oneplus/aston --depth=1
git clone https://github.com/gaurav-paul9/android_device_oneplus_sm8550-common.git -b lineage-23.0 device/oneplus/sm8550-common --depth=1
git clone https://github.com/gaurav-paul9/android_kernel_oneplus_sm8550.git -b lineage-23.0 kernel/oneplus/sm8550 --depth=1
git clone https://github.com/LineageOS/android_kernel_oneplus_sm8550-modules.git -b lineage-23.0 kernel/oneplus/sm8550-modules --depth=1
git clone https://github.com/LineageOS/android_kernel_oneplus_sm8550-devicetrees.git -b lineage-23.0 kernel/oneplus/sm8550-devicetrees --depth=1
git clone https://github.com/LineageOS/android_hardware_oplus.git -b lineage-23.0 hardware/oplus --depth=1
git clone https://github.com/inferno0230/hardware_dolby.git -b sixteen hardware/dolby --depth=1
git clone https://github.com/TheMuppets/proprietary_vendor_oneplus_aston.git -b lineage-23.0 vendor/oneplus/aston --depth=1
git clone https://github.com/TheMuppets/proprietary_vendor_oneplus_sm8550-common.git -b lineage-23.0 vendor/oneplus/sm8550-common --depth=1
send_raw "✅ *All repos cloned successfully!* 🧱"

# 🍳 Clean Build
. build/envsetup.sh
send_raw "🔐 *Generating private signing keys...* 🔑"; gk -s
send_raw "✅ *Signing keys generated successfully!* ⚙️"; axion aston gms core
BUILD_START_CLEAN=$(date +%s)
ax -br -j$(nproc --all) otapackage 2>&1 | tee out/error_clean.log & BUILD_PID=$!
monitor_progress "$BUILD_PID" "Clean Build" &; wait $BUILD_PID
CLEAN_TIME=$(( $(date +%s) - BUILD_START_CLEAN ))

ROM1=$(find out/target/product/aston -type f -name "axion*.zip" | tail -n1)
L1=$(upload_rom "$ROM1"); S1=$(du -h "$ROM1" | cut -f1)
[ "$L1" = "UPLOAD_ERROR" ] && send_raw "✅ *Clean Build Complete!* ❌ Upload Failed 🕓 $(elapsed $CLEAN_TIME)" || send_raw "✅ *Clean Build Complete!*  
📎 $(basename "$ROM1")  
📦 ${S1}  
🔗 [PixelDrain Link](${L1})  
🕓 Duration: $(elapsed $CLEAN_TIME)"

# 🔑 Rooted Build
send_raw "🔑 *Starting Rooted Build (KernelSU)* 🚀"
rm -rf kernel/oneplus/sm8550; git clone https://github.com/gaurav-paul9/android_kernel_oneplus_sm8550.git -b newroot kernel/oneplus/sm8550 --depth=1
. build/envsetup.sh
send_raw "🔐 *Generating private signing keys (Rooted Build)...* 🔑"; gk -s
send_raw "✅ *Signing keys ready!* ⚙️"; axion aston gms core
BUILD_START_ROOT=$(date +%s)
ax -br -j$(nproc --all) otapackage 2>&1 | tee out/error_root.log & BUILD_PID=$!
monitor_progress "$BUILD_PID" "Rooted Build - KernelSU" &; wait $BUILD_PID
ROOT_TIME=$(( $(date +%s) - BUILD_START_ROOT )); TOTAL_TIME=$(( CLEAN_TIME + ROOT_TIME ))

ROM2=$(find out/target/product/aston -type f -name "axion*.zip" | tail -n1)
L2=$(upload_rom "$ROM2"); S2=$(du -h "$ROM2" | cut -f1)
[ "$L2" = "UPLOAD_ERROR" ] && send_raw "✅ *Rooted Build Complete!* ❌ Upload Failed ⏳ $(elapsed $ROOT_TIME)" || send_raw "✅ *Rooted Build (KernelSU) Complete!*  
📎 $(basename "$ROM2")  
📦 ${S2}  
🔗 [PixelDrain Link](${L2})  
⏳ Root Build Duration: $(elapsed $ROOT_TIME)  
🕓 Total Duration: $(elapsed $TOTAL_TIME)"

send_raw "🎉 *AxionOS Dual Build Cycle Completed!*  
🧼 [Clean Build](${L1})  
🔑 [Rooted Build](${L2})  
🕓 Clean: $(elapsed $CLEAN_TIME)  
⏳ Root: $(elapsed $ROOT_TIME)  
🕓 Total: $(elapsed $TOTAL_TIME)  
_Ready to flash and enjoy!_ ⚡"
