# rpi-bt-radio

Headless internet radio for Raspberry Pi, streaming to a Bluetooth speaker.

Uses mpv + PulseAudio + BlueZ with automatic reconnection and recovery from
all the ways a Pi Zero's Bluetooth audio stack can fall over.

## What it handles

- **Speaker power-cycled** — reconnects and restarts playback
- **PulseAudio transport goes stale** — full PA + BT reset cycle
- **bluetoothctl hangs** — all D-Bus calls have timeouts
- **Stream drops / WiFi flakes** — mpv retries automatically
- **mpv memory leaks** — monitor kills mpv if sink disappears, gets a fresh process

## Requirements

- Raspberry Pi (tested on Pi Zero W, Raspbian Bullseye)
- A paired Bluetooth speaker
- Packages: `mpv`, `pulseaudio`, `pulseaudio-module-bluetooth`, `bluez`

## Setup

1. Pair your Bluetooth speaker:
   ```
   bluetoothctl
   > scan on
   > pair XX:XX:XX:XX:XX:XX
   > trust XX:XX:XX:XX:XX:XX
   > connect XX:XX:XX:XX:XX:XX
   > quit
   ```

2. Edit `radio.sh` — set `BTADDR` to your speaker's MAC and `STREAM` to your
   station URL (or export them as environment variables).

3. Add to `/etc/rc.local` (before `exit 0`):
   ```sh
   su - pi -c "screen -dm -S radio /home/pi/radio.sh"
   ```

4. Optionally, reduce memory pressure on a Pi Zero by disabling services
   you don't need:
   ```
   sudo systemctl disable --now man-db.timer cups cups-browsed cups.path colord ModemManager
   ```

5. Set up the resilience layer (see below) so the box self-recovers from
   hangs and network loss.

## Resilience

A Pi Zero W running 24/7 will eventually hard-freeze or drop off WiFi. Two
independent watchdogs keep it alive without a manual power-cycle.

### Hardware watchdog (full system hangs)

The BCM2835 SoC has a hardware watchdog. Let systemd drive it — if the kernel
hangs, the SoC resets in ~14s. Edit `/etc/systemd/system.conf`:

```ini
RuntimeWatchdogSec=14
ShutdownWatchdogSec=2min
```

Then `sudo systemctl daemon-reexec`. Confirm with `dmesg | grep -i watchdog`
(should say "Set hardware watchdog to 14s").

### Network watchdog (WiFi-only lockups)

The hardware watchdog can NOT catch a WiFi chip lockup where the kernel is
still alive (systemd keeps petting the watchdog, so it never fires). On a Pi
Zero W the only interface is `wlan0`, so a wedged `brcmfmac` makes the box
unreachable while it's technically "running".

`net-watchdog.sh` + `net-watchdog.service` fill that gap: ping the gateway
every 30s and escalate — soft recovery (bounce `wlan0` + restart
`wpa_supplicant`) after ~90s, full reboot only as a last resort after ~180s.
Every step is logged to the (persistent) journal under tag `net-watchdog`, so
failures are diagnosable after the fact.

```sh
sudo cp net-watchdog.sh /usr/local/sbin/
sudo chmod +x /usr/local/sbin/net-watchdog.sh
sudo cp net-watchdog.service /etc/systemd/system/
sudo systemctl enable --now net-watchdog.service
```

Note: it can't tell "my WiFi died" from "the AP died", so if your router is
down for >3 min it will reboot the Pi. Harmless for a kitchen radio.

### Persistent journal (so you can debug crashes)

Without this, logs vanish on every reboot and crashes leave no trace. The Pi
also has no RTC, so enable persistence to at least keep per-boot history:

```sh
sudo mkdir -p /var/log/journal
sudo systemctl restart systemd-journald
```

Caveat: with no RTC, wall-clock timestamps across boots are unreliable
(fake-hwclock restores a stale time until NTP syncs). Don't trust
`journalctl --list-boots` times or `last`/wtmp for crash timelines.
A cheap DS3231 RTC module fixes this.

## How it works

```
┌─────────────┐     ┌────────────┐     ┌───────────┐     ┌─────────────┐
│  radio.sh   │────▶│    mpv     │────▶│ PulseAudio│────▶│ BT Speaker  │
│ (monitor +  │     │ (stream)   │     │ (routing)  │     │ (A2DP sink) │
│  reconnect) │     └────────────┘     └───────────┘     └─────────────┘
└─────────────┘
       │
       ├── ensure_bt(): checks connection + sink state
       ├── reset_audio(): full PA/BT recovery cycle
       └── monitor loop: kills stale mpv if sink vanishes
```

Resilience layers (independent of the radio script):

```
  kernel hang  ──▶ systemd RuntimeWatchdog ──▶ BCM2835 SoC reset (~14s)
  wlan0 wedged ──▶ net-watchdog.service     ──▶ bounce wlan0, then reboot
```

## License

Public domain / CC0.
