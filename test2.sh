#!/bin/bash
# Axion_LiveProgress_Test.sh - Simulates build updates + PixelDrain test upload
set -euo pipefail

SECRETS_FILE=""
if [ -f ".env" ]; then SECRETS_FILE=".env"; elif [ -f ".env/secrets.env" ]; then SECRETS_FILE=".env/secrets.env"; fi
[ -z "$SECRETS_FILE" ] && echo "No secrets found" && exit 1
set -o allexport; source "$SECRETS_FILE"; set +o allexport

send_raw(){ curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" -d chat_id="${TG_CHAT_ID}" -d parse_mode="Markdown" --data-urlencode "text=$1"; }
edit_msg(){ curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/editMessageText" -d chat_id="${TG_CHAT_ID}" -d message_id="$1" -d parse_mode="Markdown" --data-urlencode "text=$2" >/dev/null; }

msg=$(send_raw "⚙️ *Build In Progress* for *AxionOS on aston* ℹ️\n━━━━━━━━━━━━━━━━━━━━━━\n👤 *User:* Gaurav Paul\n📊 *Progress:* [░░░░░░░░░░░░░░░░░░░░] 0.00%\n🧩 *Actions:* 0/100\n❗ *Failed Actions:* 0\n⏳ *Elapsed:* 0s\n\n_Compiling like a champ!_ 💨")
ID=$(echo "$msg"|grep -o '"message_id":[0-9]*'|cut -d: -f2)

for i in $(seq 0 20); do
  p=$((i*5)); [ "$p" -gt 100 ] && p=100
  filled=$((p/5)); bar=$(printf '%0.s█' $(seq 1 $filled); printf '%0.s░' $(seq $((filled+1)) 20))
  actions=$((i*5)); fails=$((i%7))
  edit_msg "$ID" "⚙️ *Build In Progress* for *AxionOS on aston* ℹ️\n━━━━━━━━━━━━━━━━━━━━━━\n👤 *User:* Gaurav Paul\n📊 *Progress:* [${bar}] ${p}.00%\n🧩 *Actions:* ${actions}/100\n❗ *Failed Actions:* ${fails}\n⏳ *Elapsed:* $((i*5))s\n\n_Compiling like a champ!_ 💨"
  sleep 5
done

echo "AxionOS Test Upload $(date)" > axion_test.txt
R=$(curl -s -u ":${PIXELDRAIN_API_KEY}" -F "file=@axion_test.txt" https://pixeldrain.com/api/file)
FID=$(echo "$R"|grep -o '"id":"[^"]*'|cut -d'"' -f4)
if [ -n "$FID" ]; then
  LINK="https://pixeldrain.com/u/${FID}"
  edit_msg "$ID" "✅ *Test Complete!*\n🔗 ${LINK}\n🎯 All integrations OK."
else
  edit_msg "$ID" "❌ *Test Failed!* ${R}"
fi
rm -f axion_test.txt
