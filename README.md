# NVIDIA Fan Curve (Linux)

Simple custom GPU fan curve daemon for NVIDIA cards on Linux using `nvidia-settings`.

Tested on Ubuntu 25 with a GTX 1070 Ti.

## Quick Start (Copy/Paste)

From this repository directory:

```bash
sudo install -m 755 nvidia-fan-curve.sh /usr/local/bin/nvidia-fan-curve.sh
sudo install -m 644 nvidia-fan-curve.service /etc/systemd/system/nvidia-fan-curve.service
sudo systemctl daemon-reload
sudo systemctl enable --now nvidia-fan-curve.service
sudo systemctl status nvidia-fan-curve.service --no-pager
journalctl -u nvidia-fan-curve.service -f
```

If the service starts and logs lines like `temp=53C speed=53%`, it is working.

## Requirements

- NVIDIA proprietary driver installed
- `nvidia-smi` and `nvidia-settings` available
- Xorg/Xwayland session with CoolBits enabled for fan control
- `systemd`

## 1) Script setup

Copy script:

```bash
sudo install -m 755 nvidia-fan-curve.sh /usr/local/bin/nvidia-fan-curve.sh
```

Edit curve points if needed:

- `CURVE_POINTS`
- `MIN_SPEED`
- `MAX_SPEED`
- `POLL_SECONDS`

## Fan Curve Tuning (Easy Mode)

Open the script:

```bash
sudo nano /usr/local/bin/nvidia-fan-curve.sh
```

Edit this block:

```bash
CURVE_POINTS=(
  "10:30"
  "35:30"
  "40:40"
  "55:55"
  "65:70"
  "75:85"
  "82:100"
)
```

Format is `"TEMP_C:FAN_PERCENT"`.

- Higher fan percent at a temp = cooler GPU, more noise
- Lower fan percent at a temp = quieter GPU, more heat
- Keep temps increasing top-to-bottom
- Keep fan speeds increasing top-to-bottom

Then restart:

```bash
sudo systemctl restart nvidia-fan-curve.service
journalctl -u nvidia-fan-curve.service -n 30 --no-pager
```

### Example Presets

Quiet:

```bash
CURVE_POINTS=(
  "30:25"
  "45:35"
  "60:50"
  "70:65"
  "80:85"
  "84:100"
)
```

Cooling-first (gaming):

```bash
CURVE_POINTS=(
  "30:35"
  "45:50"
  "55:65"
  "65:80"
  "72:90"
  "78:100"
)
```

## 2) Service setup

Install service:

```bash
sudo install -m 644 nvidia-fan-curve.service /etc/systemd/system/nvidia-fan-curve.service
sudo systemctl daemon-reload
sudo systemctl enable --now nvidia-fan-curve.service
```

View logs:

```bash
journalctl -u nvidia-fan-curve.service -f
```

## 3) CoolBits example

Create `/etc/X11/xorg.conf.d/20-nvidia.conf`:

```conf
Section "Device"
    Identifier "NVIDIA Card"
    Driver "nvidia"
    VendorName "NVIDIA Corporation"
    Option "Coolbits" "4"
EndSection
```

Then reboot or restart your display manager.

## Troubleshooting

- `Operation not permitted for the current user`: run as the provided root systemd service, not a user service.
- `The control display is undefined`: X auth/display are not available to the service yet; ensure graphical session is up and retry.
- Fan changes work manually with `sudo` but not service: check `sudo systemctl status nvidia-fan-curve.service` and `journalctl -u nvidia-fan-curve.service -n 100`.
- No logs or no service: run `sudo systemctl daemon-reload` then `sudo systemctl enable --now nvidia-fan-curve.service`.

## Notes

- The provided service uses `/run/user/1000/.mutter-Xwaylandauth.*` by default. Change `1000` if your UID differs.
- This was built for single-GPU systems. For multi-GPU, adjust `GPU_INDEX` and `FAN_INDEX`.
- Run at your own risk. Monitor thermals after changing the curve.
