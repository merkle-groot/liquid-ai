#!/bin/sh
# Archives LFM3 Chat and uploads it to App Store Connect / TestFlight.
# Requires: paid Apple Developer Program membership, Xcode signed into that account,
# and an App Store Connect app record for com.vishnuprakash.lfm3chat.
set -eu
cd "$(dirname "$0")/.."
[ -d Vendor/build-apple/llama.xcframework ] || scripts/fetch-llama.sh
xcodegen generate

BUILD="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"   # TestFlight needs a unique build number per upload
rm -rf build/LFM3Chat.xcarchive
xcodebuild -project LFM3Chat.xcodeproj -scheme LFM3Chat -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/LFM3Chat.xcarchive \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD" archive

sed 's#<string>export</string>#<string>upload</string>#' ExportOptions.plist > build/ExportOptions-upload.plist
xcodebuild -exportArchive -archivePath build/LFM3Chat.xcarchive \
  -exportOptionsPlist build/ExportOptions-upload.plist -exportPath build/upload -allowProvisioningUpdates
echo "Uploaded build $BUILD. It appears in App Store Connect → TestFlight after processing (~5-15 min)."
