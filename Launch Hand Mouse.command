#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -d "build/Hand Mouse.app" ]; then bash scripts/build.sh; fi
open "build/Hand Mouse.app"
