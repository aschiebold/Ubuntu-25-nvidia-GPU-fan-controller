#!/usr/bin/env bash
set -euo pipefail

UNIT="nvidia-fan-curve.service"

RESULT="$(systemctl show "$UNIT" -p Result --value 2>/dev/null || true)"
SUBSTATE="$(systemctl show "$UNIT" -p SubState --value 2>/dev/null || true)"
EXEC_STATUS="$(systemctl show "$UNIT" -p ExecMainStatus --value 2>/dev/null || true)"
LAST_LOG="$(journalctl -u "$UNIT" -n 1 --no-pager -o cat 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-300 || true)"

/usr/bin/logger -t nvidia-fan-curve-onfailure \
  "unit=$UNIT result=${RESULT:-unknown} substate=${SUBSTATE:-unknown} exec_status=${EXEC_STATUS:-unknown} last_log='${LAST_LOG:-none}' hint='check: systemctl status $UNIT && journalctl -u $UNIT -n 80 --no-pager'"
