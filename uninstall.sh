#!/usr/bin/env bash
# Uninstaller for the headless NVIDIA fan curve daemon. Must run as root.
# Does NOT touch gdm autologin (revert that manually if you enabled it).
set -euo pipefail

BIN_DST=/usr/local/bin/nvidia-fan-curve.sh
UNIT_DST=/etc/systemd/system/nvidia-fan-curve.service

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

echo "==> Stopping and disabling the service"
systemctl disable --now nvidia-fan-curve.service 2>/dev/null || true

echo "==> Removing files"
rm -f "$UNIT_DST" "$BIN_DST"

echo "==> Reloading systemd"
systemctl daemon-reload

echo "Done. (Fan control returns to the GPU's automatic mode.)"
echo "If you enabled gdm autologin via install.sh --autologin, revert it in"
echo "/etc/gdm3/custom.conf (a timestamped .bak was saved next to it)."
