#!/bin/bash
# The iPhone app (iOS/Cra.xcodeproj) in the iOS Simulator, without opening Xcode or the
# Simulator window: the device boots headless and is looked at through screenshots.
#
#   scripts/ios.sh build              # build into build/ios
#   scripts/ios.sh run [args…]        # build, install, launch; args go to the app
#                                     # (-CraDataDir fresh, -CraOpenURL https://example.com)
#   scripts/ios.sh shot <file.png>    # screenshot of the simulator
#   scripts/ios.sh test [only…]       # the UI tests (iOS/CraUITests); `only` as CraUITests/Class/test.
#                                     # Their screenshots land in build/ios/test-screens
#   scripts/ios.sh open               # show the Simulator window
#   scripts/ios.sh device             # build for the connected iPhone, install and launch it
#                                     # (CRA_IOS_DEVICE=<udid> picks one; Xcode signs it)
#
# CRA_IOS_SIM names the simulator (default "Pane iPhone 17"); it is created on the newest
# installed iOS runtime when missing. Xcode needs the iOS platform that matches its SDK:
# `xcodebuild -downloadPlatform iOS` fetches it.
set -euo pipefail
cd "$(dirname "$0")/.."

SIM_NAME="${CRA_IOS_SIM:-Pane iPhone 17}"
DERIVED="build/ios"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/Cra.app"
BUNDLE_ID="uz.pane.ios"

device() {
  local udid
  udid="$(xcrun simctl list devices available | awk -v name="$SIM_NAME" -F '[()]' 'index($0, name " (") { print $2; exit }')"
  if [ -z "$udid" ]; then
    local runtime type
    runtime="$(xcrun simctl list runtimes | awk '/^iOS/ { id = $NF } END { print id }')"
    type="$(xcrun simctl list devicetypes | awk -F '[()]' '/^iPhone 17 \(/ { print $2; exit }')"
    [ -n "$type" ] || type="$(xcrun simctl list devicetypes | awk -F '[()]' '/^iPhone/ { id = $2 } END { print id }')"
    udid="$(xcrun simctl create "$SIM_NAME" "$type" "$runtime")"
  fi
  echo "$udid"
}

boot() {
  xcrun simctl boot "$1" 2>/dev/null || true
  xcrun simctl bootstatus "$1" -b >/dev/null
}

build() {
  local udid="$1"
  xcodebuild -project iOS/Cra.xcodeproj -scheme Cra -configuration Debug \
    -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$DERIVED" build 2>&1 |
    grep -E "error|warning: [^M]|BUILD (SUCCEEDED|FAILED)" || true
  [ -d "$APP" ] || { echo "build failed" >&2; exit 1; }
}

command="${1:-run}"
shift || true

# Pane's iPhone (14 Nov 2026): signed by the Mac's team, GWSB8L799B, a free Apple team, so Xcode
# makes a 7-day profile for the phone (-allowProvisioningUpdates registers the app ids). The phone
# has to be connected and unlocked, trust this Mac, and have Developer Mode on.
if [ "$command" = device ]; then
  phone="${CRA_IOS_DEVICE:-}"
  if [ -z "$phone" ]; then
    json="$(mktemp)"
    xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1 || true
    phone="$(python3 -I - "$json" <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
for d in devices:
    hw, conn = d.get("hardwareProperties", {}), d.get("connectionProperties", {})
    if hw.get("platform") == "iOS" and conn.get("tunnelState") == "connected":
        print(hw.get("udid", ""))
        break
PY
)"
    rm -f "$json"
  fi
  [ -n "$phone" ] || { echo "no iPhone connected: plug it in or put it on this Mac's Wi-Fi, unlock it, trust this Mac, turn on Developer Mode" >&2; exit 1; }
  xcodebuild -project iOS/Cra.xcodeproj -scheme Cra -configuration Debug -destination "platform=iOS,id=$phone" \
    -derivedDataPath "$DERIVED" -allowProvisioningUpdates build 2>&1 | grep -E "error|warning: [^M]|BUILD (SUCCEEDED|FAILED)" || true
  device_app="$DERIVED/Build/Products/Debug-iphoneos/Cra.app"
  [ -d "$device_app" ] || { echo "build failed" >&2; exit 1; }
  xcrun devicectl device install app --device "$phone" "$device_app"
  xcrun devicectl device process launch --device "$phone" "$BUNDLE_ID" || true
  exit 0
fi

UDID="$(device)"

case "$command" in
  build)
    build "$UDID"
    ;;
  run)
    build "$UDID"
    boot "$UDID"
    xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
    xcrun simctl install "$UDID" "$APP"
    xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@"
    ;;
  shot)
    boot "$UDID"
    xcrun simctl io "$UDID" screenshot "${1:?usage: scripts/ios.sh shot <file.png>}" >/dev/null 2>&1
    echo "$1"
    ;;
  test)
    boot "$UDID"
    only=()
    for name in "$@"; do only+=("-only-testing:$name"); done
    rm -rf "$DERIVED/test.xcresult" "$DERIVED/test-screens"
    xcodebuild -project iOS/Cra.xcodeproj -scheme Cra -configuration Debug \
      -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DERIVED" \
      -resultBundlePath "$DERIVED/test.xcresult" \
      ${only[@]+"${only[@]}"} test 2>&1 |
      grep -E "error|Test Case .*(passed|failed)|Executed|TEST (SUCCEEDED|FAILED)|BUILD FAILED" || true
    # The screenshots the tests attached, as build/ios/test-screens/<name>.png.
    if [ -d "$DERIVED/test.xcresult" ]; then
      xcrun xcresulttool export attachments --path "$DERIVED/test.xcresult" --output-path "$DERIVED/test-screens" >/dev/null 2>&1 || true
      python3 -I - "$DERIVED/test-screens" <<'PY' || true
import json, os, sys
folder = sys.argv[1]
manifest = os.path.join(folder, "manifest.json")
if os.path.exists(manifest):
    for test in json.load(open(manifest)):
        for item in test.get("attachments", []):
            name = item.get("suggestedHumanReadableName", "")
            source = os.path.join(folder, item.get("exportedFileName", ""))
            # "name_0_<uuid>.png" as attached by XCTest: the screenshots keep the name the test
            # gave them; XCTest's own attachments (recordings, hierarchy dumps) keep theirs.
            if name.endswith(".png") and "_0_" in name and os.path.exists(source):
                os.replace(source, os.path.join(folder, name.split("_0_")[0] + ".png"))
PY
    fi
    ;;
  open)
    boot "$UDID"
    open -a Simulator --args -CurrentDeviceUDID "$UDID"
    ;;
  *)
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
