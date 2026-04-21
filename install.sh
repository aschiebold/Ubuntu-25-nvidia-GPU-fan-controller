#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo ./install.sh"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -m 755 "${SCRIPT_DIR}/nvidia-fan-curve.sh" /usr/local/bin/nvidia-fan-curve.sh
install -m 644 "${SCRIPT_DIR}/nvidia-fan-curve.service" /etc/systemd/system/nvidia-fan-curve.service

systemctl daemon-reload
systemctl enable --now nvidia-fan-curve.service

echo
echo "Install complete."
echo "Service status:"
systemctl --no-pager --full status nvidia-fan-curve.service || true
echo
echo "Live logs:"
echo "  journalctl -u nvidia-fan-curve.service -f"
