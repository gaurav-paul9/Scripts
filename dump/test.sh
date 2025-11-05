#!/bin/bash
#
# AxionOS Test Script — Telegram & PixelDrain verification
# Uses .env/secrets.env for secure keys
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
echo "📨 Sending Telegram test message..."
curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
     -d chat_id="${TG_CHAT_ID}" \
     -d parse_mode="Markdown" \
     --data-urlencode "text=🚀 *AxionOS Build Server Test*\n\n✅ Telegram Bot working correctly!\n🌐 Server: $(hostname)\n🕓 Time: $(date '+%Y-%m-%d %H:%M:%S')" \
     > /dev/null && echo "✅ Telegram notification sent!"

# ========== PixelDrain Test ==========
echo "☁️ Testing PixelDrain upload..."
echo "This is a test file from AxionOS build server on $(date)" > test_upload.txt

response=$(curl -s -u ":${PIXELDRAIN_API_KEY}" -F "file=@test_upload.txt" https://pixeldrain.com/api/file)
file_id=$(echo "$response" | grep -o '"id":"[^"]*' | cut -d'"' -f4)

if [ -n "$file_id" ]; then
  echo "✅ PixelDrain upload successful!"
  echo "🔗 Test file link: https://pixeldrain.com/u/${file_id}"
  curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
       -d chat_id="${TG_CHAT_ID}" \
       -d parse_mode="Markdown" \
       --data-urlencode "text=☁️ *PixelDrain Upload Test Successful!*\n\n🔗 [Click to View Test File](https://pixeldrain.com/u/${file_id})"
else
  echo "❌ PixelDrain upload failed!"
  echo "Response: $response"
  curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
       -d chat_id="${TG_CHAT_ID}" \
       -d parse_mode="Markdown" \
       --data-urlencode "text=❌ *PixelDrain Upload Test Failed!*\n\n${response}"
fi

rm -f test_upload.txt
echo "✅ All tests completed!"