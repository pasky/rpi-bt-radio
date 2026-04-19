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

## License

Public domain / CC0.
