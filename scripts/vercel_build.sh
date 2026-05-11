#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git /tmp/flutter
  export PATH="/tmp/flutter/bin:$PATH"
fi

flutter config --enable-web
flutter pub get
flutter build web --release \
  --dart-define=CAREAGENT_API_BASE_URL="${CAREAGENT_API_BASE_URL:-}" \
  --dart-define=FIREBASE_API_KEY="${FIREBASE_API_KEY:-}" \
  --dart-define=FIREBASE_APP_ID="${FIREBASE_APP_ID:-}" \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID="${FIREBASE_MESSAGING_SENDER_ID:-}" \
  --dart-define=FIREBASE_PROJECT_ID="${FIREBASE_PROJECT_ID:-}" \
  --dart-define=FIREBASE_AUTH_DOMAIN="${FIREBASE_AUTH_DOMAIN:-}" \
  --dart-define=FIREBASE_STORAGE_BUCKET="${FIREBASE_STORAGE_BUCKET:-}"
