#!/usr/bin/env bash
# Unit tests always; integration tests against MySQL with --mysql
# (root@localhost without password; creates and drops sqlviewer_test*).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
[[ "${1:-}" == "--mysql" ]] && export SQLVIEWER_TEST_MYSQL=1
swift test ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"}  # bash 3.2-safe empty expansion
