#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
exec bash make-dmg.sh "$@"
