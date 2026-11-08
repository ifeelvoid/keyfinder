#!/bin/bash
# Build both products without launching the app or installing plugins.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
PLUGIN_OPTIONS=()
PREVIEW=false
SKIP_PLUGINS=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --apple-silicon-preview) PREVIEW=true; shift ;;
        --skip-plugins) SKIP_PLUGINS=true; shift ;;
        --juce-dir|--build-dir)
            [ "$#" -ge 2 ] && [ -n "$2" ] && [[ "$2" != --* ]] || { echo "Missing value: $1" >&2; exit 2; }
            PLUGIN_OPTIONS+=("$1" "$2"); shift 2 ;;
        --help|-h)
            echo 'Usage: build-all.sh [--apple-silicon-preview] [--skip-plugins] [--juce-dir PATH] [--build-dir PATH]'
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done
if $PREVIEW; then bash "$ROOT/build-app.sh" --apple-silicon-preview; else bash "$ROOT/build-app.sh"; fi
if ! $SKIP_PLUGINS; then
    bash "$ROOT/install-vst.sh" --build-only ${PLUGIN_OPTIONS[@]+"${PLUGIN_OPTIONS[@]}"}
fi
echo 'Build complete.'
