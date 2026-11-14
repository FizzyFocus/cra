#!/bin/bash
# Prints the identity a local build signs with (scripts/build.sh, scripts/dev.sh):
# CRA_SIGN_IDENTITY when set ("-" for ad-hoc), else the SHA-1 of the Mac's first Apple
# Development identity, else "-" (ad-hoc).
# A certificate's designated requirement (bundle id and certificate) is the same every build,
# so the Keychain's "Always Allow" for Pane Safe Storage holds across rebuilds; an ad-hoc
# signature is new each build, and macOS asks again (13 Nov 2026).
set -euo pipefail
if [ -n "${CRA_SIGN_IDENTITY:-}" ]; then
  echo "$CRA_SIGN_IDENTITY"
  exit 0
fi
id="$( (security find-identity -v -p codesigning 2>/dev/null || true) \
  | sed -n 's/^ *[0-9][0-9]*) \([0-9A-F]\{40\}\) "Apple Development: .*"$/\1/p' | head -1)"
echo "${id:--}"
