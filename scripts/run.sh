#!/bin/bash
# Build (if needed) and launch Pane. Pass --rebuild to force a build.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" = "--rebuild" ] || [ ! -d build/Pane.app ]; then scripts/build.sh "${2:-release}"; fi
env -u ELECTRON_RUN_AS_NODE open -n build/Pane.app --args "${@:3}"
