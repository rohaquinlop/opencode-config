#!/usr/bin/env bash
# Shared mode definitions for the be-terse hook and the /be-terse:mode command.
# Sourced, never executed. Keeps both sides agreeing on the valid modes and on
# where the persisted mode lives.

BE_TERSE_MODES=(ste caveman)
BE_TERSE_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/be-terse"
BE_TERSE_STATE_FILE="$BE_TERSE_STATE_DIR/mode"

be_terse_is_mode() {
  local candidate="$1" mode
  for mode in "${BE_TERSE_MODES[@]}"; do
    [[ "$candidate" == "$mode" ]] && return 0
  done
  return 1
}

be_terse_persist_mode() {
  mkdir -p "$BE_TERSE_STATE_DIR" && printf '%s\n' "$1" >"$BE_TERSE_STATE_FILE"
}

be_terse_persisted_mode() {
  local mode=""
  [[ -r "$BE_TERSE_STATE_FILE" ]] && read -r mode <"$BE_TERSE_STATE_FILE"
  printf '%s' "$mode"
}
