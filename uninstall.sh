#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo ./uninstall.sh"
  exit 1
fi

if systemctl list-unit-files | awk '{print $1}' | grep -qx "nvidia-fan-curve.service"; then
  systemctl disable --now nvidia-fan-curve.service || true
  systemctl stop nvidia-fan-curve-failure.service || true
  systemctl daemon-reload
fi

rm -f /etc/systemd/system/nvidia-fan-curve.service
rm -f /etc/systemd/system/nvidia-fan-curve-failure.service
rm -f /usr/local/bin/nvidia-fan-curve.sh
rm -f /usr/local/sbin/nvidia-fan-curve-onfailure.sh

echo
echo "Uninstall complete."
echo "Removed:"
echo "  /etc/systemd/system/nvidia-fan-curve.service"
echo "  /etc/systemd/system/nvidia-fan-curve-failure.service"
echo "  /usr/local/bin/nvidia-fan-curve.sh"
echo "  /usr/local/sbin/nvidia-fan-curve-onfailure.sh"
echo
echo "Note: CoolBits/Xorg configuration was left unchanged."
