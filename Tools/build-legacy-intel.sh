#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Personal Intel build. Never installed or published unless explicitly requested.
set -euo pipefail
cd "$(dirname "$0")/.."
export VORSSAINT_ARCH=x86_64
export VORSSAINT_DEV_APP_NAME='Vorssaint (Legacy Intel)'
export VORSSAINT_DEV_OPTIMIZED=1
exec ./build.sh --dev "$@"
