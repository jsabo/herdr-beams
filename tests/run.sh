#!/usr/bin/env bash
# Lint and unit-test the plugin offline. Set HERDR_BEAMS_INTEGRATION=1 to also
# run the live test, which creates and deletes one real Beam.
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

shellcheck bin/*.sh demo/*.sh tests/fakes/* tests/run.sh
bash -n bin/*.sh demo/*.sh
bats --print-output-on-failure tests/unit

if [ "${HERDR_BEAMS_INTEGRATION:-}" = 1 ]; then
  bats --print-output-on-failure tests/integration
fi
