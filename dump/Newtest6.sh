#!/bin/bash
# === AxionOS Dual Build Test v11 ===
# No jq needed. Reliable progress & working PixelDrain links (~30s total).

set -euo pipefail
set -o allexport; source .env/secrets.env; set +o allexport

# --- Telegram helpers ---
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

# --- PixelDrain upload (grep-only) ---
upload_test_file() {
  local name="$1"
  echo "AxionOS test file for ${name} build $(date)" > "${name}.txt"
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

# --- Create first Telegram message ---
msg=$(send_raw "⚙️ *Build In Progress (Clean Build)* for *AxionOS on aston* ℹ️
━━━━━━━━━━━━━━━━━━━━━━
👤 *User:* Gaurav Paul
📊 *Progress:* [░░░░░░░░░░░░░░░░░░░░] 0%
⏳ *Elapsed:* 0s

_Compiling like a champ!_ 💨")

MSG_ID=$(echo "$msg" | grep -o '"message_id":[0-9]\+' | cut -d: -f2 | head -n1 || echo "")
USE_EDIT=1
if [ -z "$MSG_ID" ]; then
  echo "⚠️ Could not extract message_id. Using send mode only."
  USE_EDIT=0
fi

# --- Progress simulator ---
simulate_progress() {
  local stage="$1"
  local steps="$2"
  local sleep_s="$3"
  local i
  for i in $(seq 0 "$steps"); do
    local p=$(( (i*100)/steps ))
    local filled=$((p/5))
    local bar="$(printf '█%.0s' $(seq 1 $filled); printf '░%.0s' $(seq $((filled+1)) 20))"
    local text="⚙️ *Build In Progress ($stage)* for *AxionOS on aston* ℹ️
━━━━━━━━━━━━━━━━━━━━━━
👤 *User:* Gaurav Paul
📊 *Progress:* [${bar}] ${p}%
⏳ *Elapsed:* $((i*sleep_s))s

_Update $i — compiling..._ 💨"
    if [ "$USE_EDIT" -eq 1 ]; then
      edit_raw "$MSG_ID" "$text" >/dev/null 2>&1 || send_raw "$text" >/dev/null 2>&1
    else
      send_raw "$text" >/dev/null 2>&1
    fi
    sleep "$sleep_s"
  done
  local done_text="✅ *$stage Completed!*  
━━━━━━━━━━━━━━━━━━━━━━  
📦 Finalizing upload... ⏳"
  if [ "$USE_EDIT" -eq 1 ]; then
    edit_raw "$MSG_ID" "$done_text" >/dev/null 2>&1 || send_raw "$done_text" >/dev/null 2>&1
  else
    send_raw "$done_text" >/dev/null 2>&1
  fi
  sleep 2
}

# --- Clean build simulation ---
simulate_progress "Clean Build" 3 5
L1=$(upload_test_file "clean_test")
if [ "$L1" = "UPLOAD_ERROR" ]; then
  send_raw "🧼 *Clean Build Complete!*  
━━━━━━━━━━━━━━━━━━━━━━  
❌ Upload Failed (no PixelDrain ID returned)
🕓 Duration: 0h:00m:15s"
else
  send_raw "🧼 *Clean Build Complete!*  
━━━━━━━━━━━━━━━━━━━━━━  
🔗 [PixelDrain Link](${L1})
🕓 Duration: 0h:00m:15s"
fi

# --- Reset message for root build ---
if [ "$USE_EDIT" -eq 1 ]; then
  edit_raw "$MSG_ID" "⚙️ *Build In Progress (Rooted Build - KernelSU)* for *AxionOS on aston* ℹ️
━━━━━━━━━━━━━━━━━━━━━━
👤 *User:* Gaurav Paul
📊 *Progress:* [░░░░░░░░░░░░░░░░░░░░] 0%
⏳ *Elapsed:* 0s

_Compiling like a champ!_ 💨" >/dev/null 2>&1
else
  send_raw "⚙️ *Build In Progress (Rooted Build - KernelSU)* for *AxionOS on aston* ℹ️
━━━━━━━━━━━━━━━━━━━━━━
👤 *User:* Gaurav Paul
📊 *Progress:* [░░░░░░░░░░░░░░░░░░░░] 0%
⏳ *Elapsed:* 0s

_Compiling like a champ!_ 💨" >/dev/null 2>&1
fi

# --- Rooted build simulation ---
simulate_progress "Rooted Build - KernelSU" 3 5
L2=$(upload_test_file "root_test")
if [ "$L2" = "UPLOAD_ERROR" ]; then
  send_raw "🔑 *Rooted Build (KernelSU) Complete!*  
━━━━━━━━━━━━━━━━━━━━━━  
❌ Upload Failed (no PixelDrain ID returned)
⏳ Root Build Duration: 0h:00m:15s
🕓 Total Duration: 0h:00m:30s"
else
  send_raw "🔑 *Rooted Build (KernelSU) Complete!*  
━━━━━━━━━━━━━━━━━━━━━━  
🔗 [PixelDrain Link](${L2})
⏳ Root Build Duration: 0h:00m:15s
🕓 Total Duration: 0h:00m:30s"
fi

# --- Final summary ---
send_raw "🎉 *AxionOS Dual Build Cycle Completed!*  
━━━━━━━━━━━━━━━━━━━━━━
🧼 *Clean Build* → ${L1}  
🔑 *Rooted Build (KernelSU)* → ${L2}

🕓 *Clean Duration:* 0h:00m:15s  
⏳ *Root Duration:* 0h:00m:15s  
🕓 *Total Duration:* 0h:00m:30s

_AxionOS built clean & rooted like a champ!_ ⚡"