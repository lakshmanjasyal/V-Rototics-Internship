# RoboticBell Kiosk

Robot powers on → Linux auto-logs in → Waydroid opens → RoboticBell launches.
All automatic. Teachers manage power via Ctrl+Alt+Q password dialog.

## Structure

```
roboticbell-kiosk/
├── install.sh                   ← run this ONCE per robot
├── uninstall.sh                 ← revert everything
├── diagnose.sh                  ← troubleshoot when something breaks
├── README.md
├── modules/
│   ├── 00_common.sh             (helpers - sourced)
│   ├── 01_waydroid_usb.sh       (ESP32 USB passthrough)
│   ├── 02_autologin.sh          (GDM auto-login)
│   ├── 03_kiosk.sh              (Waydroid + RoboticBell auto-launch + speedup)
│   └── 04_teacher_control.sh    (Ctrl+Alt+Q + instant-wake)
└── runtime/
    └── teacher-shutdown.sh      (installed to /usr/local/bin/)
```

Just 4 modules. Everything you need, nothing you don't.

## Setup (per robot)

```bash
# 1. Ubuntu 24.04 Desktop installed, user v-robotics7 created
# 2. Logged in as v-robotics7 on Wayland session
# 3. Waydroid installed and initialized:
sudo apt install -y waydroid && sudo waydroid init

# 4. RoboticBell APK installed inside Waydroid:
waydroid app install /path/to/RoboticBell.apk

# 5. Run installer:
tar xzf roboticbell-kiosk.tar.gz
cd roboticbell-kiosk
chmod +x install.sh uninstall.sh diagnose.sh modules/*.sh runtime/*.sh
./install.sh
# (will prompt to set the teacher password)

# 6. Reboot:
sudo reboot
```

## Boot timing

| Action               | Time         |
|----------------------|--------------|
| First cold boot      | 30-45 sec    |
| **Daily wake**       | **3-5 sec**  |
| Restart              | 30-45 sec    |
| Press power = Sleep  | 1 sec        |

Train teachers to press the power button (which suspends) at end of day,
NOT shutdown. Wake is 3-5 sec, feels instant.

## Daily use

| Action          | How                                              |
|-----------------|--------------------------------------------------|
| Turn ON / Wake  | Press power button (3-5 sec wake from suspend)   |
| Sleep           | Press power button OR Ctrl+Alt+Q → Sleep         |
| Restart         | Ctrl+Alt+Q → password → Restart                  |
| Full shutdown   | Ctrl+Alt+Q → password → Shut Down (weekly use)   |

## If something breaks

```bash
./diagnose.sh           # 20+ checks; shows what's broken with fix command
./diagnose.sh --fix     # auto-repair fixable problems
./diagnose.sh --report  # generate support bundle for V-Robotics
```

The diagnostic prints each problem with: what's wrong, why, and a one-line fix.

## Different username?

If not using `v-robotics7`, edit one line BEFORE running install:

```bash
sed -i 's/KIOSK_USER="v-robotics7"/KIOSK_USER="YOUR_NAME"/' modules/00_common.sh
```

All modules read from this one variable.

## What each module does

- **01_waydroid_usb** — injects USB host feature into vendor.img, sets uevent forwarding, udev rule, blacklists cdc_acm. (The hard-won USB passthrough fix.)
- **02_autologin** — GDM auto-login so robot reaches desktop without password.
- **03_kiosk** — pre-warms Waydroid at boot (in parallel with Linux), kiosk launcher script, user systemd service, disables unused services, hides GRUB. (Auto-start + speedup combined.)
- **04_teacher_control** — Ctrl+Alt+Q shortcut, teacher dialog, configures power button to suspend (instant wake).

## Uninstall

```bash
./uninstall.sh
sudo reboot
```

Reverts all changes: removes systemd units, udev rule, cdc_acm blacklist,
GDM auto-login, GRUB tweaks. Restores vendor.img from backup.
