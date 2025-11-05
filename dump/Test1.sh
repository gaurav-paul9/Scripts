#!/bin/bash
#
# AxionOS Test Script — Telegram & PixelDrain verification (v2)
# Beautiful message formatting + Emoji layout
#

set -euo pipefail

# ========== Load Secrets ==========
SECRETS_FILE=""
if [ -f ".env" ]; then
  SECRETS_FILE=".env"
elif [ -f ".env/secrets.env" ]; then
  SECRETS_FILE=".env/secrets.env"
fi

if [ -z "$SECRETS_FILE" ]; then
  echo "❌ No secrets file found (.env or .env/secrets.env)"
  exit 1
fi

set -o allexport
source "$SECRETS_FILE"
set +o allexport

[ -z "${TG_BOT_TOKEN:-}" ] && echo "Missing TG_BOT_TOKEN" && exit 1
[ -z "${TG_CHAT_ID:-}" ] && echo "Missing TG_CHAT_ID" && exit 1
[ -z "${PIXELDRAIN_API_KEY:-}" ] && echo "Missing PIXELDRAIN_API_KEY" && exit 1

# ========== Telegram Test ==========
SERVER_NAME=$(hostname)
TIME_NOW=$(date '+%Y-%m-%d %H:%M:%S')

read -r -d '' TELEGRAM_MSG <<EOF || true
🚀 *AxionOS Build Server — Test Ping*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ *Telegram Bot:* Working perfectly  
💻 *Server:* ${SERVER_NAME}  
🕓 *Time:* ${TIME_NOW}

☁️ Next: Testing PixelDrain upload...
EOF

echo "📨 Sending Telegram test message..."
curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
     -d chat_id="${TG_CHAT_ID}" \
     -d parse_mode="Markdown" \
     --data-urlencode "text=${TELEGRAM_MSG}" > /dev/null
echo "✅ Telegram message sent!"

# ========== PixelDrain Test ==========
echo "☁️ Testing PixelDrain upload..."
echo "This is a test file from AxionOS Build Server on ${TIME_NOW}" > test_upload.txt

response=$(curl -s -u ":${PIXELDRAIN_API_KEY}" -F "file=@test_upload.txt" https://pixeldrain.com/api/file)
file_id=$(echo "$response" | grep -o '"id":"[^"]*' | cut -d'"' -f4)

if [ -n "$file_id" ]; then
  TEST_LINK="https://pixeldrain.com/u/${file_id}"
  echo "✅ PixelDrain upload successful!"
  echo "🔗 Test link: ${TEST_LINK}"

  read -r -d '' PIXELDRAIN_MSG <<EOF || true
☁️ *PixelDrain Upload Test Successful!*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📄 *File:* test_upload.txt  
🕓 *Uploaded:* ${TIME_NOW}  
🔗 [Click to View Test File](${TEST_LINK})

🎯 Both Telegram & PixelDrain integrations verified successfully!
EOF

  curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
       -d chat_id="${TG_CHAT_ID}" \
       -d parse_mode="Markdown" \
       --data-urlencode "text=${PIXELDRAIN_MSG}" > /dev/null
else
  echo "❌ PixelDrain upload failed!"
  echo "Response: $response"

  read -r -d '' FAIL_MSG <<EOF || true
❌ *PixelDrain Upload Test Failed!*
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💬 Response:  
\`${response}\`
EOF

  curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
       -d chat_id="${TG_CHAT_ID}" \
       -d parse_mode="Markdown" \
       --data-urlencode "text=${FAIL_MSG}" > /dev/null
fi

rm -f test_upload.txt
echo "✅ All tests completed!"