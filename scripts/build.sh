#!/bin/bash
# Builds Pane.app into build/Pane.app (Cra was rebranded Pane; modules and targets keep Cra's names).
#   scripts/build.sh            release build, signed with the Mac's Apple Development
#                               identity when it has one, else ad-hoc
#   scripts/build.sh debug      debug build
#   CRA_SIGN_IDENTITY="Developer ID Application: …" scripts/build.sh
#                               distributable build (see docs/release.md)
#   CRA_SIGN_IDENTITY=- scripts/build.sh
#                               ad-hoc even when the Mac has an Apple Development identity
#   CRA_PROVISIONING_PROFILE=<path> (with CRA_SIGN_IDENTITY)
#                               adds the passkey entitlements the profile grants
#   CRA_INSTALL_DIR=<dir> scripts/build.sh
#                               also copies the app to <dir>/Pane.app
#   CRA_ARCH=x86_64 scripts/build.sh
#                               builds for the other CPU (arm64 or x86_64) into
#                               build/<arch>/Pane.app, with that CPU's CEF in
#                               vendor/cef-<arch> and SwiftPM's files in build/swiftpm-<arch>
# Dev builds are version 0.0.0-dev and stay unregistered with LaunchServices, so
# opening Pane (or a pane:// link) always picks the installed release.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
CONFIG="${1:-release}"
VERSION="${CRA_VERSION:-0.0.0-dev}"
BUILD_NUMBER="${CRA_BUILD:-$(date +%Y%m%d%H%M)}"

# The host CPU keeps the usual paths; the other one gets its own CEF, SwiftPM folder and
# app, so building it never replaces vendor/cef (worktrees share it) or build/Pane.app.
# scripts/release.sh finds the app with the same rule.
ARCH="${CRA_ARCH:-$(uname -m)}"
case "$ARCH" in
  arm64)  CEF_PLATFORM=macosarm64 ;;
  x86_64) CEF_PLATFORM=macosx64 ;;
  *) echo "CRA_ARCH must be arm64 or x86_64, not $ARCH" >&2; exit 1 ;;
esac
if [ "$ARCH" = "$(uname -m)" ]; then
  CEF_DIR=vendor/cef
  FINAL_APP="$ROOT/build/Pane.app"
  SWIFT_ARGS=(-c "$CONFIG")
else
  CEF_DIR="vendor/cef-$ARCH"
  FINAL_APP="$ROOT/build/$ARCH/Pane.app"
  SWIFT_ARGS=(-c "$CONFIG" --arch "$ARCH" --scratch-path "$ROOT/build/swiftpm-$ARCH")
  export CRA_CEF_DIR="$ROOT/$CEF_DIR"  # read by Package.swift
fi

CEF_DIR="$CEF_DIR" CEF_ARCH="$CEF_PLATFORM" scripts/fetch-cef.sh
scripts/fetch-sparkle.sh

swift build "${SWIFT_ARGS[@]}"
BIN="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)"

# Stage the bundle, then sync it into place so the existing Pane.app directory
# keeps its identity (LaunchServices otherwise launches duplicate instances).
STAGE="$(mktemp -d /tmp/cra-stage.XXXXXX)"
APP="$STAGE/Pane.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

# The SwiftPM product keeps Cra's name; the bundle's executable is Pane (Info.plist).
cp "$BIN/Cra" "$APP/Contents/MacOS/Pane"
cp "$BIN/CraPluginHost" "$APP/Contents/MacOS/CraPluginHost"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" resources/Info.plist > "$APP/Contents/Info.plist"
# CRA_BUNDLE_ID builds under another identifier: a test build signed with one's own team and
# a provisioning profile for it (docs/release.md, "iCloud sync"). The data folder stays Pane's,
# so run such a build with CRA_DATA_DIR.
[ -n "${CRA_BUNDLE_ID:-}" ] && /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $CRA_BUNDLE_ID" "$APP/Contents/Info.plist"
# No update feed: Pane has none of its own yet, and upstream Cra's was removed (12 Nov 2026) so a
# release build never replaces Pane with a Cra release (resources/Info.plist, lint pane-bundle).
# Google API key for Safe Browsing (docs/release.md); CraCEF hands it to Chromium.
[ -n "${CRA_GOOGLE_API_KEY:-}" ] && /usr/libexec/PlistBuddy -c "Add :CraGoogleAPIKey string $CRA_GOOGLE_API_KEY" "$APP/Contents/Info.plist"
# The Keychain item the framework reads (scripts/fetch-cef.sh found it; SafeStorage.swift uses it).
if [ -s "$CEF_DIR/.cra-keychain-item" ]; then
  /usr/libexec/PlistBuddy -c "Add :CraKeychainService string '$(cat "$CEF_DIR/.cra-keychain-item")'" "$APP/Contents/Info.plist"
fi
echo -n "APPL????" > "$APP/Contents/PkgInfo"
[ -f resources/AppIcon.icns ] && cp resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# The AppleScript dictionary (Arc's, same terms and codes: Info.plist OSAScriptingDefinition).
cp resources/Cra.sdef "$APP/Contents/Resources/Cra.sdef"
[ -d resources/web ] && cp -R resources/web "$APP/Contents/Resources/web"
[ -d resources/brand ] && cp -R resources/brand "$APP/Contents/Resources/brand"
[ -d resources/blocklist ] && cp -R resources/blocklist "$APP/Contents/Resources/blocklist"
[ -d resources/browsers ] && cp -R resources/browsers "$APP/Contents/Resources/browsers"
[ -d resources/app-icons ] && cp -R resources/app-icons "$APP/Contents/Resources/app-icons"
[ -d resources/licenses ] && cp -R resources/licenses "$APP/Contents/Resources/licenses"
[ -d resources/fonts ] && cp -R resources/fonts "$APP/Contents/Resources/fonts"
cp -R resources/live-folder-plugins "$APP/Contents/Resources/live-folder-plugins"

FRAMEWORK_SRC="$ROOT/$CEF_DIR/Release/Chromium Embedded Framework.framework"
cp -R "$FRAMEWORK_SRC" "$APP/Contents/Frameworks/"
# Sparkle's XPC services are only for sandboxed apps; Cra uses Autoupdate and Updater.app.
ditto "$ROOT/vendor/sparkle/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"

# CEF needs one helper app per process type (see cef_variables.cmake,
# CEF_HELPER_APP_SUFFIXES). Format: "<name suffix>|<plist suffix>".
for entry in "|" " (Alerts)|.alerts" " (GPU)|.gpu" " (Plugin)|.plugin" " (Renderer)|.renderer"; do
  NAME_SUFFIX="${entry%%|*}"
  PLIST_SUFFIX="${entry#*|}"
  HELPER="$APP/Contents/Frameworks/Pane Helper${NAME_SUFFIX}.app"
  mkdir -p "$HELPER/Contents/MacOS"
  cp "$BIN/CraHelper" "$HELPER/Contents/MacOS/Pane Helper${NAME_SUFFIX}"
  sed -e "s/__NAME_SUFFIX__/${NAME_SUFFIX}/g" -e "s/__PLIST_SUFFIX__/${PLIST_SUFFIX}/g" \
      -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
      resources/Helper-Info.plist > "$HELPER/Contents/Info.plist"
  echo -n "APPL????" > "$HELPER/Contents/PkgInfo"
  # Chromium posts page notifications from the Alerts helper too, so macOS asks for it and lists
  # it under System Settings ▸ Notifications: Pane's name and icon there, like Arc's helper.
  if [ "$NAME_SUFFIX" = " (Alerts)" ]; then
    mkdir -p "$HELPER/Contents/Resources"
    cp resources/AppIcon.icns "$HELPER/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Pane" -c "Add :CFBundleIconFile string AppIcon" \
      -c "Add :NSUserNotificationAlertStyle string alert" "$HELPER/Contents/Info.plist"
  fi
done

# The Dock tile plug-in (Info.plist NSDockTilePlugIn), a SwiftPM dynamic library in a bundle.
DOCK_TILE="$APP/Contents/PlugIns/CraDockTile.docktileplugin"
mkdir -p "$DOCK_TILE/Contents/MacOS"
cp "$BIN/libCraDockTile.dylib" "$DOCK_TILE/Contents/MacOS/CraDockTile"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" resources/DockTile-Info.plist > "$DOCK_TILE/Contents/Info.plist"

# Every executable must run on the CPU this build is for (Sparkle ships universal).
for exe in "$APP/Contents/MacOS/Pane" "$APP/Contents/MacOS/CraPluginHost" "$APP"/Contents/Frameworks/*.app/Contents/MacOS/* \
           "$DOCK_TILE/Contents/MacOS/CraDockTile" \
           "$APP/Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework" \
           "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"; do
  lipo "$exe" -verify_arch "$ARCH" || { echo "$exe has no $ARCH code: $(lipo -archs "$exe")" >&2; exit 1; }
done

# Code signing, innermost first. Set CRA_SIGN_IDENTITY to a "Developer ID Application: …"
# identity for a distributable build with the hardened runtime, timestamps and the CEF
# entitlements; scripts/release.sh then notarizes the result.
# Without it, a local build signs with the Mac's own Apple Development identity when it has
# one (13 Nov 2026), as an ad-hoc build otherwise would (no hardened runtime, timestamp or
# entitlements). Its designated requirement (bundle id and certificate) stays the same across
# rebuilds, so the Keychain's "Always Allow" for Pane Safe Storage holds; an ad-hoc signature
# is a new one each build, and macOS asks again after every install.
IDENTITY="${CRA_SIGN_IDENTITY:--}"
LOCAL_IDENTITY=""
if [ -z "${CRA_SIGN_IDENTITY:-}" ]; then
  LOCAL_IDENTITY="$( (security find-identity -v -p codesigning 2>/dev/null || true) \
    | sed -n 's/^ *[0-9][0-9]*) \([0-9A-F]\{40\}\) "Apple Development: .*"$/\1/p' | head -1)"
  if [ -n "$LOCAL_IDENTITY" ]; then
    echo "Signing with the Apple Development identity $LOCAL_IDENTITY (CRA_SIGN_IDENTITY=- for ad-hoc)"
  fi
fi
sign() {  # sign <path> [entitlements]
  local target="$1" ent="${2:-}"
  if [ -n "$LOCAL_IDENTITY" ]; then
    codesign --force --sign "$LOCAL_IDENTITY" --timestamp=none "$target"
  elif [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$target"
  else
    local args=(--force --sign "$IDENTITY" --options runtime --timestamp)
    [ -n "$ent" ] && args+=(--entitlements "$ent")
    codesign "${args[@]}" "$target"
  fi
}
FW="$APP/Contents/Frameworks/Chromium Embedded Framework.framework"
find "$FW/Libraries" -name '*.dylib' -print0 2>/dev/null | while IFS= read -r -d '' lib; do sign "$lib"; done
sign "$FW"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
sign "$SPARKLE/Versions/B/Autoupdate"
sign "$SPARKLE/Versions/B/Updater.app"
sign "$SPARKLE"
sign "$APP/Contents/MacOS/CraPluginHost"
for h in "$APP"/Contents/Frameworks/*.app; do sign "$h" "$ROOT/resources/CraHelper.entitlements"; done
sign "$DOCK_TILE"
# Passkeys need entitlements only a provisioning profile can grant: the Touch ID
# keychain group ("<app id>.webauthn", scripts/cef-patches) and, once Apple approves
# it, iCloud Keychain (web-browser.public-key-credential). With
# CRA_PROVISIONING_PROFILE=<Developer ID profile> the app embeds it and claims what
# it allows; macOS refuses to launch an app that claims more. See docs/release.md.
APP_ENTITLEMENTS="$ROOT/resources/Cra.entitlements"
if [ -n "${CRA_PROVISIONING_PROFILE:-}" ] && [ "$IDENTITY" != "-" ]; then
  PB=/usr/libexec/PlistBuddy
  PROFILE="$STAGE/profile.plist"
  security cms -D -i "$CRA_PROVISIONING_PROFILE" -o "$PROFILE"
  APP_ID="$($PB -c "Print :Entitlements:com.apple.application-identifier" "$PROFILE")"
  BUNDLE_ID="$($PB -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist")"
  [ "${APP_ID#*.}" = "$BUNDLE_ID" ] || { echo "Provisioning profile is for $APP_ID, not $BUNDLE_ID" >&2; exit 1; }
  cp "$CRA_PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
  APP_ENTITLEMENTS="$STAGE/Cra.entitlements"
  cp "$ROOT/resources/Cra.entitlements" "$APP_ENTITLEMENTS"
  $PB -c "Add :com.apple.application-identifier string $APP_ID" \
      -c "Add :com.apple.developer.team-identifier string ${APP_ID%%.*}" "$APP_ENTITLEMENTS"
  if $PB -c "Print :Entitlements:keychain-access-groups" "$PROFILE" >/dev/null 2>&1; then
    $PB -c "Add :keychain-access-groups array" -c "Add :keychain-access-groups:0 string $APP_ID.webauthn" "$APP_ENTITLEMENTS"
  fi
  if [ "$($PB -c "Print :Entitlements:com.apple.developer.web-browser.public-key-credential" "$PROFILE" 2>/dev/null)" = true ]; then
    $PB -c "Add :com.apple.developer.web-browser.public-key-credential bool true" "$APP_ENTITLEMENTS"
  else
    echo "Note: the provisioning profile has no web-browser.public-key-credential; iCloud Keychain passkeys stay off" >&2
  fi
  # iCloud sync (Settings ▸ General ▸ Sync) needs the container entitlements the profile grants
  # once iCloud Documents is on for the App ID. The first container is also named in Info.plist,
  # so the folder shows in iCloud Drive as "Pane".
  if CONTAINER="$($PB -c "Print :Entitlements:com.apple.developer.ubiquity-container-identifiers:0" "$PROFILE" 2>/dev/null)"; then
    for key in com.apple.developer.ubiquity-container-identifiers com.apple.developer.icloud-container-identifiers; do
      $PB -c "Add :$key array" "$APP_ENTITLEMENTS"
      i=0
      while id="$($PB -c "Print :Entitlements:com.apple.developer.ubiquity-container-identifiers:$i" "$PROFILE" 2>/dev/null)"; do
        $PB -c "Add :$key:$i string $id" "$APP_ENTITLEMENTS"
        i=$((i + 1))
      done
    done
    $PB -c "Add :com.apple.developer.icloud-services array" -c "Add :com.apple.developer.icloud-services:0 string CloudDocuments" "$APP_ENTITLEMENTS"
    # A Developer ID profile grants Development and Production; a distributed build uses
    # Production, as Xcode's Developer ID export claims it.
    if $PB -c "Print :Entitlements:com.apple.developer.icloud-container-environment" "$PROFILE" >/dev/null 2>&1; then
      $PB -c "Add :com.apple.developer.icloud-container-environment string Production" "$APP_ENTITLEMENTS"
    fi
    $PB -c "Add :NSUbiquitousContainers dict" -c "Add :NSUbiquitousContainers:$CONTAINER dict" \
        -c "Add :NSUbiquitousContainers:$CONTAINER:NSUbiquitousContainerIsDocumentScopePublic bool true" \
        -c "Add :NSUbiquitousContainers:$CONTAINER:NSUbiquitousContainerName string Pane" \
        -c "Add :NSUbiquitousContainers:$CONTAINER:NSUbiquitousContainerSupportedFolderLevels string Any" "$APP/Contents/Info.plist"
  else
    echo "Note: the provisioning profile grants no iCloud container; iCloud sync stays off" >&2
  fi
fi
sign "$APP" "$APP_ENTITLEMENTS"
if [ "$IDENTITY" != "-" ]; then
  codesign --verify --deep --strict --verbose=2 "$APP"
fi

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
mkdir -p "$FINAL_APP"
rsync -a --delete "$APP/" "$FINAL_APP/"
"$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
rm -rf "$STAGE"
"$LSREGISTER" -u "$FINAL_APP" >/dev/null 2>&1 || true
echo "Built $FINAL_APP"

# Optional copy outside ~/Documents (an app that runs from Documents makes macOS ask
# for folder access and blocks the main thread until answered).
# The installed copy is the one macOS should know: registered (-f), so it is listed under System
# Settings ▸ Desktop & Dock ▸ Default web browser and opens pane:// and web links. `just install`.
if [ -n "${CRA_INSTALL_DIR:-}" ]; then
  INSTALL_APP="$CRA_INSTALL_DIR/Pane.app"
  mkdir -p "$CRA_INSTALL_DIR"
  rsync -a --delete "$FINAL_APP/" "$INSTALL_APP/"
  "$LSREGISTER" -f "$INSTALL_APP" >/dev/null 2>&1 || true
  echo "Installed and registered $INSTALL_APP"
fi
