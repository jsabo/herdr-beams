#!/usr/bin/env bash
cd "$(dirname "$0")/.." || exit 1
# shellcheck disable=SC1091
. bin/common.sh
require_config
exec bash bin/beam-agent.sh --profile "${BEAM_CLAUDE_PROFILE:-claude-opus}" "$@"
