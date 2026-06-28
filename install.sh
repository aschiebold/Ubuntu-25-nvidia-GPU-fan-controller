#!/usr/bin/env bash
# Installer for the headless NVIDIA fan curve daemon.
#
#   sudo ./install.sh                 # install + enable the service
#   sudo ./install.sh --autologin USR # also enable gdm autologin for user USR
#
# Must run as root.
set -euo pipefail

BIN_DST=/usr/local/bin/nvidia-fan-curve.sh
UNIT_DST=/etc/systemd/system/nvidia-fan-curve.service
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AUTOLOGIN_USER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --autologin) AUTOLOGIN_USER="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

echo "==> Installing daemon to $BIN_DST"
install -o root -g root -m 0755 "$HERE/nvidia-fan-curve.sh" "$BIN_DST"

echo "==> Installing unit to $UNIT_DST"
install -o root -g root -m 0644 "$HERE/nvidia-fan-curve.service" "$UNIT_DST"

if [[ -n "$AUTOLOGIN_USER" ]]; then
  GDM_CONF=""
  for c in /etc/gdm3/custom.conf /etc/gdm/custom.conf; do
    [[ -f "$c" ]] && GDM_CONF="$c" && break
  done
  if [[ -z "$GDM_CONF" ]]; then
    echo "!! No gdm custom.conf found; skipping autologin setup." >&2
  else
    echo "==> Enabling gdm autologin for '$AUTOLOGIN_USER' in $GDM_CONF"
    cp -a "$GDM_CONF" "$GDM_CONF.bak.$(date +%Y%m%d-%H%M%S)"
    if grep -qE '^[[:space:]]*AutomaticLoginEnable[[:space:]]*=[[:space:]]*true' "$GDM_CONF"; then
      echo "   autologin already enabled; leaving as-is"
    else
      awk -v u="$AUTOLOGIN_USER" '
        { print }
        /^\[daemon\]/ && !done { print "AutomaticLoginEnable=true"; print "AutomaticLogin=" u; done=1 }
      ' "$GDM_CONF" > "$GDM_CONF.new" && mv "$GDM_CONF.new" "$GDM_CONF"
    fi
    # Lingering lets the user's session/runtime dir persist across logins.
    loginctl enable-linger "$AUTOLOGIN_USER" || true
  fi
fi

echo "==> Reloading systemd and enabling the service"
systemctl daemon-reload
systemctl enable --now nvidia-fan-curve.service

echo "==> Status"
systemctl --no-pager --full status nvidia-fan-curve.service | head -n 12 || true

cat <<'EOF'

Installed. Notes:
  * Fan control needs an NVIDIA NV-CONTROL (X/Xwayland) endpoint. The daemon
    discovers one from the active graphical session (logged-in user or the gdm
    greeter). To guarantee one exists from boot with nobody logged in, enable
    autologin:  sudo ./install.sh --autologin <username>
  * Logs:   journalctl -u nvidia-fan-curve.service -f
  * Tune the curve by editing /usr/local/bin/nvidia-fan-curve.sh (CURVE_POINTS)
    then: sudo systemctl restart nvidia-fan-curve.service
EOF
