# nvidia-fan-curve

A small, resilient **temperature → fan-speed curve daemon** for NVIDIA GPUs on
Linux that keeps working **whether or not a user is logged in, and with the
screen on or off**.

It is a single Bash script driven by `nvidia-smi` (to read temperature) and
`nvidia-settings` (to set fan speed), wrapped in a hardened systemd service.

Developed and tested on **Ubuntu 26.04** with a **GeForce GTX 1070 Ti** and
driver **580.173.02**, GNOME on Wayland (gdm).

---

## Why this exists

On Linux, setting a manual fan speed on a consumer NVIDIA GPU is awkward:

- **`nvidia-smi` cannot set fan speed.** It can read temperature and fan %, and
  set a *target temperature* (`-gtt`), but not drive the fan directly.
- **Fan control goes through `nvidia-settings`**, which requires a running
  **NV-CONTROL (X / Xwayland) endpoint**.
- On a Wayland desktop the only X endpoint is the **Xwayland** belonging to a
  graphical session. A naive service that hard-codes `DISPLAY=:0` and one user's
  X authority **fails for ~minutes at every boot** (restart-looping until that
  user logs in) and **stops working when the session goes away**.
- You can't sidestep this with a second, dedicated headless `Xorg` for fan
  control either: the desktop's compositor (`gnome-shell`) holds the GPU's
  **DRM master**, so a second X server can't acquire it while the desktop runs.

This daemon solves the practical problem by **reusing whatever NV-CONTROL
endpoint is available** and **never giving up**:

- Reads temperature via `nvidia-smi` (no X needed).
- **Discovers** a usable endpoint automatically by probing the runtime dirs of
  the logged-in user **and** the gdm greeter (`/run/user/<uid>/`), trying their
  `Xwayland` auth files against displays `:0`/`:1` and verifying each with a real
  NV-CONTROL query.
- If no endpoint exists yet, it **waits and retries** (the GPU stays on its safe
  built-in automatic fan control) instead of exiting — so systemd never enters a
  restart loop.
- **Reconnects automatically** if the session changes (e.g. greeter → user
  login, logout, lock/unlock, RDP connect/disconnect).
- Hands fan control **back to automatic** on stop/exit.

To *guarantee* an endpoint exists from boot with nobody at the keyboard, enable
**gdm autologin** (see below). With autologin the curve engages within seconds
of boot.

---

## Repository contents

| File | Purpose |
|------|---------|
| `nvidia-fan-curve.sh` | The daemon. Edit `CURVE_POINTS` here to tune the curve. |
| `nvidia-fan-curve.service` | systemd unit (runs the daemon as root). |
| `install.sh` | Installs the daemon + unit, enables the service; optional autologin. |
| `uninstall.sh` | Stops/removes everything (returns fan control to automatic). |
| `LICENSE` | MIT. |

---

## Requirements

- NVIDIA proprietary driver with `nvidia-smi` and `nvidia-settings` installed.
- systemd.
- A graphical session that provides an X/Xwayland endpoint (GNOME/gdm tested).
  For login-independent operation, gdm **autologin** (the installer can set it up).

---

## Install

```bash
git clone <your-repo-url> nvidia-fan-curve
cd nvidia-fan-curve

# Install and enable the service:
sudo ./install.sh

# ...or also enable gdm autologin so fan control runs from boot with no login:
sudo ./install.sh --autologin <your-username>
```

Then watch it work:

```bash
journalctl -u nvidia-fan-curve.service -f
```

Example log output:

```
nvidia-fan-curve daemon starting (headless / session-independent)
no NV-CONTROL X endpoint yet; GPU on default auto fan; retry in 10s
using NV-CONTROL endpoint DISPLAY=:0 XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.2Y8KR3
temp=42C speed=51%
temp=41C speed=51% (held by hysteresis)
```

---

## Configuration

All knobs live at the top of `nvidia-fan-curve.sh`:

```bash
GPU_INDEX=0
FAN_INDEX=0
POLL_SECONDS=3            # how often to sample temperature
RECONNECT_SECONDS=10      # retry interval when no X endpoint is available

# Curve points: "tempC:speedPercent" (linearly interpolated between points)
CURVE_POINTS=(
  "10:30"
  "35:40"
  "40:50"
  "55:55"
  "65:70"
  "75:85"
  "82:100"
)

MIN_SPEED=25              # clamp
MAX_SPEED=100
HYSTERESIS_PERCENT=2      # only re-apply when the target moves more than this

# UIDs whose runtime dir may host a usable Xwayland (1000=first user, 984=gdm).
CANDIDATE_UIDS=(1000 984)
CANDIDATE_DISPLAYS=(":0" ":1")
```

After editing, restart the service:

```bash
sudo systemctl restart nvidia-fan-curve.service
```

> If your primary user's UID isn't 1000, or your distro's gdm UID differs from
> 984, update `CANDIDATE_UIDS` accordingly (`id -u <user>`, `id -u gdm`).

---

## Autologin & security note

Guaranteeing fan control from boot with **no one logged in** requires a graphical
session to exist at boot. The simplest reliable way is **gdm autologin**, which
`install.sh --autologin <user>` configures in `/etc/gdm3/custom.conf`:

```ini
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=<user>
```

**Security implication:** autologin means the machine boots straight into that
user's desktop, so anyone with physical access reaches it without a password.
Only enable it on machines where that is acceptable. A timestamped backup of
`custom.conf` is saved next to it, and you can revert by removing those two
lines.

If you skip autologin, the daemon still works while a user is logged in (or
whenever the gdm greeter happens to expose an Xwayland endpoint), and it idles
safely (GPU automatic fan control) the rest of the time.

---

## Uninstall

```bash
sudo ./uninstall.sh
```

This stops and removes the service and script; the GPU returns to automatic fan
control. Autologin (if you enabled it) is left untouched — revert it manually.

---

## Troubleshooting

- **Service active but fan not changing / log says "no NV-CONTROL endpoint":**
  there is no graphical session with an Xwayland yet. Log in, or enable
  autologin. Confirm an endpoint manually:
  ```bash
  XAUTH=$(ls /run/user/1000/.mutter-Xwaylandauth.* | head -1)
  sudo env DISPLAY=:0 XAUTHORITY="$XAUTH" nvidia-settings -q [gpu:0]/GPUFanControlState -t
  ```
- **Check current fan state:**
  ```bash
  nvidia-smi --query-gpu=temperature.gpu,fan.speed --format=csv,noheader
  ```
- **Wrong UIDs:** adjust `CANDIDATE_UIDS` in the script (see Configuration).

---

## How it behaves across session events

| Event | Behavior |
|-------|----------|
| Boot, autologin on | Endpoint appears within seconds; curve engages (no restart loop). |
| Boot, no autologin | Idles on GPU auto fan; engages as soon as a session exists. |
| Screen lock (`Win+L`) | Session/Xwayland stay alive → keeps controlling, uninterrupted. |
| Monitor off (DPMS) | Unaffected. |
| Logout / session change | Endpoint lost → daemon re-discovers the next one automatically. |
| `systemctl stop` | Graceful exit; fan control handed back to automatic. |

---

## License

MIT — see [LICENSE](LICENSE).
