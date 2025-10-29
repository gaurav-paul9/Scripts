#!/bin/bash
set -euo pipefail
set -o allexport; source .env/secrets.env; set +o allexport

send(){ curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/$1" "${@:2}"; }
send_raw(){ send sendMessage -d chat_id="$TG_CHAT_ID" -d parse_mode=Markdown --data-urlencode "text=$1"; }
edit(){ send editMessageText -d chat_id="$TG_CHAT_ID" -d message_id="$1" -d parse_mode=Markdown --data-urlencode "text=$2" >/dev/null; }

progress(){
  local id="$1" stage="$2"
  for i in $(seq 0 20); do
    p=$((i*5)); [ $p -gt 100 ] && p=100
    filled=$((p/5)); bar=$(printf '%0.s█' $(seq 1 $filled); printf '%0.s░' $(seq $((filled+1)) 20))
    edit "$id" "⚙️ *Build In Progress ($stage)* for *AxionOS on aston* ℹ️
━━━━━━━━━━━━━━━━━━━━━━
👤 *User:* Gaurav Paul
📊 *Progress:* [${bar}] ${p}%
⏳ *Elapsed:* $((i*3))s

_Compiling like a champ!_ 💨"
    sleep 3
  done
}

msg=$(send_raw "⚙️ *Build In Progress (Clean Build)* for *AxionOS on aston* ℹ️
━━━━━━━━━━━━━━━━━━━━━━
👤 *User:* Gaurav Paul
📊 *Progress:* [░░░░░░░░░░░░░░░░░░░░] 0%
⏳ *Elapsed:* 0s"); ID=$(echo "$msg"|grep -o '"message_id":[0-9]*'|cut -d: -f2)
progress "$ID" "Clean Build"
echo "Clean build done" > clean_test.txt
L1=$(curl -s -u ":$PIXELDRAIN_API_KEY" -F "file=@clean_test.txt" https://pixeldrain.com/api/file|grep -o '"id":"[^"]*'|cut -d'"' -f4)
send_raw "🧼 *Clean Build Complete!*
━━━━━━━━━━━━━━━━━━━━━━
🔗 [PixelDrain Link](https://pixeldrain.com/u/$L1)
🕓 *Duration:* 0h:00m:30s"

progress "$ID" "Rooted Build - KernelSU"
echo "Root build done" > root_test.txt
L2=$(curl -s -u ":$PIXELDRAIN_API_KEY" -F "file=@root_test.txt" https://pixeldrain.com/api/file|grep -o '"id":"[^"]*'|cut -d'"' -f4)
send_raw "🔑 *Rooted Build (KernelSU) Complete!*
━━━━━━━━━━━━━━━━━━━━━━
🔗 [PixelDrain Link](https://pixeldrain.com/u/$L2)
⏳ *Root Build Duration:* 0h:00m:30s
🕓 *Total Duration:* 0h:01m:00s"

send_raw "🎉 *AxionOS Dual Build Cycle Completed!*
━━━━━━━━━━━━━━━━━━━━━━
🧼 *Clean Build* → [PixelDrain Link](https://pixeldrain.com/u/$L1)
🔑 *Rooted Build (KernelSU)* → [PixelDrain Link](https://pixeldrain.com/u/$L2)
🕓 *Total Build Time:* 0h:01m:00s
_AxionOS built, rooted & ready to flash!_ ⚡"
rm -f clean_test.txt root_test.txt