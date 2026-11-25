#!/bin/bash
# Builds the app and uploads it to App Store Connect (then TestFlight), signed in the cloud with the team's
# App Store Connect API key. The key stays outside the repo: ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
#   ./release.sh            # build number = the date and time, so every upload is new
set -euo pipefail
cd "$(dirname "$0")"
KEY_ID="${ASC_KEY_ID:-U7X675X4W9}"
ISSUER="${ASC_ISSUER_ID:-5ecaaa41-9750-4e81-9457-48cc40ba7241}"
KEY="$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"
[ -f "$KEY" ] || { echo "Missing $KEY (the App Store Connect API key)"; exit 1; }
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$KEY" -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER")
BUILD="$(date +%Y%m%d%H%M)"
xcodegen generate >/dev/null
rm -rf build/SOR.xcarchive build/export
xcodebuild -project SOR.xcodeproj -scheme SOR -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/SOR.xcarchive CURRENT_PROJECT_VERSION="$BUILD" "${AUTH[@]}" archive | grep -E 'error:|ARCHIVE'
xcodebuild -exportArchive -archivePath build/SOR.xcarchive -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export "${AUTH[@]}" 2>&1 | grep -E 'error:|Upload succeeded|EXPORT'
echo "Uploaded build $BUILD. It shows up in App Store Connect › TestFlight after Apple processes it (usually 5–30 minutes)."
