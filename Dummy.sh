#!/bin/bash
# =========================================================
#  AxionOS Dual Build Simulation v12 (Dry Run)
#  ✅ Full structure of production v12, no real build
#  ✅ Safe 1-min test: cleanup + sync + clone + build sim
# =========================================================

set -eEuo pipefail
trap 'send_raw "💥 *Simulation Failed!* at line $LINENO."' ERR

# --- Load secrets ---
set -o allexport
source .env/secrets.env
set +o allexport

# --- Telegram Functions ---
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
  local name="$1"
  echo "Dry-run test file for $name build" > "${name}.txt"
  local resp
  resp=$(curl -s -u ":${PIXELDRAIN_API_KEY}" -F "file=@${name}.txt" https://pixeldrain.com/api/file || echo "")
  rm -f "${name}.txt"
  local id
  id=$(echo "$resp" | grep -oE '"id":"[^"]+"' | head -n1 | cut -d'"' -f4 || echo "")
  if [ -z "$id" ]; then
    echo "UPLOAD_ERROR"
  else
    echo "https://pixeldrain.com/u/${id}"
  fi
}

elapsed() {
  printf "%02dh:%02dm:%02ds" $(( $1/3600 )) $(( ($1/60)%60 )) $(( $1%60 ))
}

# --- Start simulation ---
msg=$(send_raw "🧪 *AxionOS Build Simulation Started*  
━━━━━━━━━━━━━━━━━━━━━━  
👤 *User:* Gaurav Paul  
🧱 *Mode:* Dual Build (Clean + Root)  
⏳ *Elapsed:* 0s  

_Testing all systems..._ ⚙️")

MSG_ID=$(echo "$msg" | grep -o '"message_id":[0-9]\+' | cut -d: -f2 | head -n1 || echo "")
USE_EDIT=1
[ -z "$MSG_ID" ] && USE_EDIT=0

# --- Simulated progress function ---
simulate_progress() {
  local stage="$1"
  local steps=6
  local sleep_s=5
  for i in $(seq 0 $steps); do
    local p=$(( (i*100)/steps ))
    local filled=$((p/5))
    local bar="$(printf '█%.0s' $(seq 1 $filled); printf '░%.0s' $(seq $((filled+1)) 20))"
    local text="⚙️ *AxionOS Simulation*  
━━━━━━━━━━━━━━━━━━━━━━  
🏗️ *Stage:* ${stage}  
📊 *Progress:* [${bar}] ${p}%  
⏳ *Elapsed:* $((i*sleep_s))s  

_Simulating build process..._ 💨"
    if [ "$USE_EDIT" -eq 1 ]; then
      edit_raw "$MSG_ID" "$text" >/dev/null 2>&1 || send_raw "$text" >/dev/null 2>&1
    else
      send_raw "$text" >/dev/null 2>&1
    fi
    sleep "$sleep_s"
  done
  if [ "$USE_EDIT" -eq 1 ]; then
    edit_raw "$MSG_ID" "✅ *${stage} Complete!*  
━━━━━━━━━━━━━━━━━━━━━━  
📦 Finalizing upload... ⏳" >/dev/null 2>&1
  else
    send_raw "✅ *${stage} Complete!*  
━━━━━━━━━━━━━━━━━━━━━━  
📦 Finalizing upload... ⏳" >/dev/null 2>&1
  fi
  sleep 2
}

# =========================================================
# 🧹 CLEANUP SIMULATION
# =========================================================
send_raw "🧹 *Cleaning old build directories (simulated)* ♻️"
sleep 2
send_raw "✅ *Cleanup Complete!*  
━━━━━━━━━━━━━━━━━━━━━━  
_Removed old sources (simulated)._ 🧼"

# =========================================================
# 🧼 CLEAN BUILD SIMULATION
# =========================================================
send_raw "🧼 *Initializing Clean Build (simulated)* 🚀"
sleep 2
send_raw "🧠 *Repo initialized successfully!*  
_Removing old Clang prebuilts (simulated)._ 🔧"
sleep 2
send_raw "🔁 *Syncing sources via /opt/crave/resync.sh (simulated)* ⏳"
sleep 2

# =========================================================
# 🔗 CLONING REPOS (simulated)
# =========================================================
send_raw "📦 *Cloning device, kernel, and vendor repositories (simulated)* ⏬"
sleep 3
send_raw "✅ *All device, kernel, hardware, and vendor repos cloned!*  
━━━━━━━━━━━━━━━━━━━━━━  
_Ready to start lunch and compilation._ 🧱"

# =========================================================
# 🧩 CLEAN BUILD SIMULATION
# =========================================================
simulate_progress "Clean Build"
L1=$(upload_rom "dry_clean")
CLEAN_TIME=25

if [ "$L1" = "UPLOAD_ERROR" ]; then
  send_raw "🧼 *Clean Build Complete!*  
━━━━━━━━━━━━━━━━━━━━━━  
❌ Upload Failed  
🕓 Duration: $(elapsed $CLEAN_TIME)"
else
  send_raw "🧼 *Clean Build Complete!*  
━━━━━━━━━━━━━━━━━━━━━━  
🔗 [PixelDrain Link](${L1})  
🕓 Duration: $(elapsed $CLEAN_TIME)"
fi

# =========================================================
# 🔑 ROOTED BUILD SIMULATION
# =========================================================
simulate_progress "Rooted Build (KernelSU)"
L2=$(upload_rom "dry_root")
ROOT_TIME=25
TOTAL_TIME=$(( CLEAN_TIME + ROOT_TIME ))

if [ "$L2" = "UPLOAD_ERROR" ]; then
  send_raw "🔑 *Rooted Build (KernelSU) Complete!*  
━━━━━━━━━━━━━━━━━━━━━━  
❌ Upload Failed  
⏳ Root Build Duration: $(elapsed $ROOT_TIME)  
🕓 Total Duration: $(elapsed $TOTAL_TIME)"
else
  send_raw "🔑 *Rooted Build (KernelSU) Complete!*  
━━━━━━━━━━━━━━━━━━━━━━  
🔗 [PixelDrain Link](${L2})  
⏳ Root Build Duration: $(elapsed $ROOT_TIME)  
🕓 Total Duration: $(elapsed $TOTAL_TIME)"
fi

# =========================================================
# 🎉 FINAL SUMMARY
# =========================================================
send_raw "🎉 *AxionOS Dry Run Completed Successfully!*  
━━━━━━━━━━━━━━━━━━━━━━  
🧼 *Clean Build:* [PixelDrain Link](${L1})  
🔑 *Rooted Build:* [PixelDrain Link](${L2})  

🕓 *Clean Duration:* $(elapsed $CLEAN_TIME)  
⏳ *Root Duration:* $(elapsed $ROOT_TIME)  
🕓 *Total Duration:* $(elapsed $TOTAL_TIME)  

_All systems functional — ready for real build!_ ⚡"