#!/usr/bin/env bash
# Backs the /be-terse:mode command. Prints a single status line.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/mode.sh"

requested="${1:-status}"
valid=$(printf '%s|' "${BE_TERSE_MODES[@]}"); valid="${valid%|}"

show_status() {
  local persisted; persisted=$(be_terse_persisted_mode)
  if [[ -n "${BE_TERSE_MODE:-}" ]]; then
    echo "active mode: ${BE_TERSE_MODE} (from \$BE_TERSE_MODE, overrides the saved mode)"
    if [[ -n "$persisted" ]]; then echo "saved mode: $persisted (takes effect once \$BE_TERSE_MODE is unset)"; fi
  elif [[ -n "$persisted" ]]; then
    echo "active mode: $persisted (saved)"
  else
    echo "active mode: ste (default, nothing saved yet)"
  fi
}

case "$requested" in
  status)
    show_status
    ;;
  *)
    if be_terse_is_mode "$requested"; then
      be_terse_persist_mode "$requested"
      echo "mode set to: $requested (saved, survives restarts)"
      if [[ -n "${BE_TERSE_MODE:-}" ]]; then echo "warning: \$BE_TERSE_MODE=${BE_TERSE_MODE} is set for this session and overrides the saved mode"; fi
    else
      echo "unknown mode: '$requested'"
      echo "valid modes: $valid"
      show_status
    fi
    ;;
esac
