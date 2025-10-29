#!/bin/bash
# === AxionOS Dual Build Test v9 ===
# Simulates both clean & rooted builds in ~30 s with Telegram + PixelDrain upload

set -euo pipefail
set -o allexport; source .env/secrets.env; set +o allexport

# --- Telegram helpers ---
send(){ curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/$1" "${@:2}"; }
send_raw(){
  send sendMessage -d chat_id="$TG_CHAT_ID" -d parse_mode=MarkdownV2 --data-urlencode "text=$1"
}
edit(){
  send editMessageText \
    -d chat_id="$TG_CHAT_ID" \
    -d message_id="$1" \
    -d parse_mode=MarkdownV2 \
    --data-urlencode "text=$2" >/dev/null
}

# --- PixelDrain upload (fully fixed) ---
upload_test_file(){
  local name="$1"
  echo "This is a test file for $name build." > "${name}.txt"
  local resp
  resp=$(curl -s -u ":$PIXELDRAIN_API_KEY" -F "file=@${name}.txt" https://pixeldrain.com/api/file)
  rm -f "${name}.txt"

  # Try jq first (if installed), otherwise fallback to grep
  local id=""
  if command -v jq >/dev/null 2>&1; then
    id=$(echo "$resp" | jq -r '.id // empty')
  else
    id=$(echo "$resp" | grep -oE '"id":"[^"]+"' | head -n1 | cut -d'"' -f4)
  fi

  if [[ -z "$id" ]]; then
    echo "UPLOAD_ERROR"
  else
    echo "https://pixeldrain.com/u/${id}"
  fi
}

# --- Simulate progress ---
simulate_progress(){
  local id="$1" stage="$2" total_steps=6
  for i in $(seq 0 $total_steps); do
    p=$(( (i*100)/total_steps ))
    filled=$((p/5))
    bar=$(printf '█%.0s' $(seq 1 $filled); printf '░%.0s' $(seq $((filled+1)) 20))
    safe_bar=$(echo "$bar" | sed 's/\-/\\-/g; s/\_/\\_/g; s/\./\\./g')
    edit "$id" "⚙️ *Build In Progress ($stage)* for *AxionOS on aston* ℹ️
━━━━━━━━━━━━━━━━━━━━━━
👤 *User:* Gaurav Paul
📊 *Progress:* [${safe_bar}] ${p}%%
⏳ *Elapsed:* $((i*5)) s

_Compiling like a champ!_ 💨"
    sleep 5
  done
  edit "$id" "✅ *$stage Completed!*  
━━━━━━━━━━━━━━━━━━━━━━  
📦 Finalizing upload… ⏳"
  sleep 3
}

# --- Start test run ---
msg=$(send_raw "⚙️ *Build In Progress (Clean Build)* for *AxionOS on aston* ℹ️
━━━━━━━━━━━━━━━━━━━━━━
👤 *User:* Gaurav Paul
📊 *Progress:* [░░░░░░░░░░░░░░░░░░░░] 0%%
⏳ *Elapsed:* 0 s")
msg_id=$(echo "$msg" | grep -o '"message_id":[0-9]*' | cut -d: -f2)

# Clean build simulation
simulate_progress "$msg_id" "Clean Build"
L1=$(upload_test_file "clean_test")

if [[ "$L1" == "UPLOAD_ERROR" ]]; then
  send_raw "⚠️ *Clean Build Complete!*  
━━━━━━━━━━━━━━━━━━━━━━  
❌ *Upload Failed* — PixelDrain ID not returned!"
else
  send_raw "🧼 *Clean Build Complete!*
━━━━━━━━━━━━━━━━━━━━━━
🔗 [PixelDrain Link](${L1})
🕓 *Duration:* 0h 00m 15s"
fi

# Rooted build simulation
simulate_progress "$msg_id" "Rooted Build – KernelSU"
L2=$(upload_test_file "root_test")

if [[ "$L2" == "UPLOAD_ERROR" ]]; then
  send_raw "⚠️ *Rooted Build (KernelSU) Complete!*  
━━━━━━━━━━━━━━━━━━━━━━  
❌ *Upload Failed* — PixelDrain ID not returned!"
else
  send_raw "🔑 *Rooted Build (KernelSU) Complete!*
━━━━━━━━━━━━━━━━━━━━━━
🔗 [PixelDrain Link](${L2})
⏳ *Root Build Duration:* 0h 00m 15s
🕓 *Total Duration:* 0h 00m 30s"
fi

# Final summary (always sent)
send_raw "🎉 *AxionOS Dual Build Cycle Completed!*
━━━━━━━━━━━━━━━━━━━━━━
🧼 *Clean Build* → ${L1}
🔑 *Rooted Build (KernelSU)* → ${L2}

🕓 *Clean Duration:* 0h 00m 15s  
⏳ *Root Duration:* 0h 00m 15s  
🕓 *Total Duration:* 0h 00m 30s  

_AxionOS built clean & rooted like a champ!_ ⚡"