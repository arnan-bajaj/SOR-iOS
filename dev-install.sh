#!/bin/bash
# Installs a test copy on a plugged-in iPhone, signed with your free Personal Team (no paid team needed).
# It's a separate app (org.systemoverload.team.dev) and lasts 7 days. Push, universal links and the widget's live
# data need the paid team, so they're off in this copy.
#   ./dev-install.sh [personal team id]   (default: the one on this Mac)
set -euo pipefail
cd "$(dirname "$0")"
TEAM="${1:-2N8CC9ZTH9}"
DEVICE="$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && (/connected/ || /available/) {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) print $i}' | head -1)"
[ -n "$DEVICE" ] || { echo "Plug in and unlock your iPhone first."; exit 1; }
xcodegen generate >/dev/null
xcodebuild -project SOR.xcodeproj -scheme SOR -configuration Debug -destination "id=$DEVICE" -derivedDataPath build-dev \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" BUNDLE_BASE=org.systemoverload.team.dev APP_ENTITLEMENTS=tools/Dev.entitlements WIDGET_ENTITLEMENTS=tools/Dev.entitlements \
  build | grep -E 'error:|BUILD'
xcrun devicectl device install app --device "$DEVICE" build-dev/Build/Products/Debug-iphoneos/SOR.app >/dev/null
xcrun devicectl device process launch --device "$DEVICE" org.systemoverload.team.dev >/dev/null 2>&1 || echo "Installed. Open SOR Team on the phone (trust it in Settings › General › VPN & Device Management the first time)."
