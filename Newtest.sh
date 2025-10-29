#!/bin/bash
# === AxionOS Dual Build Test v4 ===
# Simulates both clean & rooted builds in ~30 seconds with PixelDrain + Telegram test.

set -euo pipefail
set -o allexport; source .env/secrets.env; set +o allexport

# --- Telegram helper functions ---
send(){ curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/$1" "${@:2}"; }
send_raw(){ send sendMessage -d chat_id="$TG_CHAT_ID" -d parse_mode=Markdown --data-urlencode "text=$1"; }
edit(){ send editMessageText -d chat_id="$TG_CHAT_ID" -d message_id="$1" -d parse_mode=Markdown --data-urlencode "text=$2" >/dev/null; }

# --- Function to simulate progress ---
simulate_progress(){
  local id="$1" stage="$2" total_steps=6
  for i in $(seq 0 $total_steps); do
    p=$(( (i*100)/$total_steps ))
    filled=$((p/5))
    bar=$(printf '%0.s█' $(seq 1 $filled); printf '%0.s░' $(seq $((filled+1)) 20))
    edit "$id" "⚙️ *Build In Progress ($stage)* for *AxionOS on aston* ℹ️
━━━━━━━━━━━━━━━━━━━━━━
👤 *User:* Gaurav Paul
📊 *Progress:* [${bar}] ${p}%
⏳ *Elapsed:* $((i*5))s

_Compiling like a champ!_ 💨"
    sleep 5
  done
  edit "$id" "✅ *$stage Completed!*  
━━━━━━━━━━━━━━━━━━━━━━  
📦 Finalizing upload... ⏳"
  sleep 2
}

# --- Function to upload dummy file to PixelDrain ---
upload_test_file(){
  local name="$1"
  echo "This is a test file for $name build." > "$name.txt"
  local id=$(curl -s -u ":$PIXELDRAIN_API_KEY" -F "file=@$name.txt" https://pixeldrain.com/api/file | grep -o '"id":"[^"]*' | cut -d'"' -f4)
  rm -f "$name.txt"
  echo "https://pixeldrain.com/u/$id"
}

# --- Start test ---
msg=$(send_raw "⚙️ *Build In Progress (Clean Build)* for *AxionOS on aston* ℹ️
━━━━━━━━━━━━━━━━━━━━━━
👤 *User:* Gaurav Paul
📊 *Progress:* [░░░░░░░░░░░░░░░░░░░░] 0%
⏳ *Elapsed:* 0s")
msg_id=$(echo "$msg" | grep -o '"message_id":[0-9]*' | cut -d: -f2)

# Clean build simulation
simulate_progress "$msg_id" "Clean Build"
L1=$(upload_test_file "clean_test")
send_raw "🧼 *Clean Build Complete!*
━━━━━━━━━━━━━━━━━━━━━━
🔗 [PixelDrain Link](${L1})
🕓 *Duration:* 0h:00m:15s"

# Rooted build simulation
simulate_progress "$msg_id" "Rooted Build - KernelSU"
L2=$(upload_test_file "root_test")
send_raw "🔑 *Rooted Build (KernelSU) Complete!*
━━━━━━━━━━━━━━━━━━━━━━
🔗 [PixelDrain Link](${L2})
⏳ *Root Build Duration:* 0h:00m:15s
🕓 *Total Duration:* 0h:00m:30s"

# Final summary
send_raw "🎉 *AxionOS Dual Build Cycle Completed!*
━━━━━━━━━━━━━━━━━━━━━━
🧼 *Clean Build* → [PixelDrain Link](${L1})
🔑 *Rooted Build (KernelSU)* → [PixelDrain Link](${L2})

🕓 *Clean Duration:* 0h:00m:15s  
⏳ *Root Duration:* 0h:00m:15s  
🕓 *Total Duration:* 0h:00m:30s  

_AxionOS built clean & rooted like a champ!_ ⚡"