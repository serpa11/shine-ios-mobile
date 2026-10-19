#!/usr/bin/env bash
#
# Builds Shine.ipa from source.
#
# This has to run on macOS. An iOS app is not just a folder of files - it needs
# an arm64 binary compiled by Xcode and a signature from Apple, and neither can
# be produced anywhere else. On Windows or Linux, use a cloud Mac (see README).
#
# Usage:
#   DEVELOPMENT_TEAM=ABCDE12345 ./scripts/build-ipa.sh
#
#   METHOD=development   (default) ad-hoc signed, needs a team ID
#   METHOD=ad-hoc        install on any device without a store account
#   METHOD=app-store     for uploading to App Store Connect / TestFlight

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="Shine"
CONFIG="Release"
ARCHIVE="build/${SCHEME}.xcarchive"
EXPORT_DIR="build/ipa"

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: this must run on macOS. Found $(uname -s)." >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is not installed. Run: brew install xcodegen" >&2
  exit 1
fi

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  cat >&2 <<'MSG'
error: DEVELOPMENT_TEAM is not set.

Find your Team ID in Xcode > Settings > Accounts, or at
https://developer.apple.com/account -> Membership.

  DEVELOPMENT_TEAM=ABCDE12345 ./scripts/build-ipa.sh
MSG
  exit 1
fi

METHOD="${METHOD:-development}"
case "$METHOD" in
  development|ad-hoc|app-store) ;;
  *)
    echo "error: METHOD must be one of: development, ad-hoc, app-store" >&2
    exit 1
    ;;
esac

mkdir -p build

# ---------------------------------------------------------------------------
# Generate the Xcode project
#
# The .xcodeproj is not committed - it is generated from project.yml, so the
# project file is never the thing that drifts out of sync with the source.
# ---------------------------------------------------------------------------

echo "==> Generating ${SCHEME}.xcodeproj from project.yml"
xcodegen generate

# ---------------------------------------------------------------------------
# Archive
# ---------------------------------------------------------------------------

echo "==> Archiving ($CONFIG)"
rm -rf "$ARCHIVE"
xcodebuild \
  -project "${SCHEME}.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  clean archive

# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

echo "==> Writing export options ($METHOD)"
cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>${METHOD}</string>
  <key>teamID</key>
  <string>${DEVELOPMENT_TEAM}</string>
  <key>stripSwiftSymbols</key>
  <true/>
</dict>
</plist>
PLIST

echo "==> Exporting IPA"
rm -rf "$EXPORT_DIR"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath "$EXPORT_DIR"

echo
echo "Done. The IPA is in ${EXPORT_DIR}/"
ls -lh "$EXPORT_DIR" || true
