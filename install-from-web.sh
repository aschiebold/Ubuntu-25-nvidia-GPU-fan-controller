#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root (sudo)."
  exit 1
fi

REPO_OWNER="aschiebold"
REPO_NAME="Ubuntu-25-nvidia-GPU-fan-controller"
REPO_REF="main"
BASE_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_REF}"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo "Downloading installer files from ${REPO_OWNER}/${REPO_NAME}@${REPO_REF}..."
curl -fsSL "${BASE_URL}/nvidia-fan-curve.sh" -o "${TMP_DIR}/nvidia-fan-curve.sh"
curl -fsSL "${BASE_URL}/nvidia-fan-curve-onfailure.sh" -o "${TMP_DIR}/nvidia-fan-curve-onfailure.sh"
curl -fsSL "${BASE_URL}/nvidia-fan-curve.service" -o "${TMP_DIR}/nvidia-fan-curve.service"
curl -fsSL "${BASE_URL}/nvidia-fan-curve-failure.service" -o "${TMP_DIR}/nvidia-fan-curve-failure.service"

install -m 755 "${TMP_DIR}/nvidia-fan-curve.sh" /usr/local/bin/nvidia-fan-curve.sh
install -m 755 "${TMP_DIR}/nvidia-fan-curve-onfailure.sh" /usr/local/sbin/nvidia-fan-curve-onfailure.sh
install -m 644 "${TMP_DIR}/nvidia-fan-curve.service" /etc/systemd/system/nvidia-fan-curve.service
install -m 644 "${TMP_DIR}/nvidia-fan-curve-failure.service" /etc/systemd/system/nvidia-fan-curve-failure.service

systemctl daemon-reload
systemctl enable --now nvidia-fan-curve.service

echo
echo "Install complete."
systemctl --no-pager --full status nvidia-fan-curve.service || true
echo
echo "Live logs:"
echo "  journalctl -u nvidia-fan-curve.service -f"
