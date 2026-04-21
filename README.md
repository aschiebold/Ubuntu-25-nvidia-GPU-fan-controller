# NVIDIA Fan Curve (Linux)

Simple custom GPU fan curve daemon for NVIDIA cards on Linux using `nvidia-settings`.

Tested on Ubuntu 25 with a GTX 1070 Ti.

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

## Notes

- The provided service uses `/run/user/1000/.mutter-Xwaylandauth.*` by default. Change `1000` if your UID differs.
- This was built for single-GPU systems. For multi-GPU, adjust `GPU_INDEX` and `FAN_INDEX`.
- Run at your own risk. Monitor thermals after changing the curve.
