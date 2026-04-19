#!/bin/bash
# Internet radio via Bluetooth speaker
#
# Streams internet radio to a paired Bluetooth speaker, with automatic
# reconnection handling and PulseAudio recovery.
#
# Configuration: set BTADDR and STREAM below, or override via environment.

BTADDR="${BTADDR:-FC:58:FA:4C:A0:20}"
STREAM="${STREAM:-http://wsdownload.bbc.co.uk/worldservice/meta/live/shoutcast/mp3/eieuk.pls}"
RETRY_INTERVAL="${RETRY_INTERVAL:-15}"
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

sleep 30

# Trust device so bluez auto-reconnects
timeout 5 bluetoothctl trust "$BTADDR"

bt_connected() {
    timeout 5 bluetoothctl info "$BTADDR" 2>/dev/null | grep -q "Connected: yes"
}

bt_sink_available() {
    timeout 5 pactl list sinks short 2>/dev/null | grep -q "bluez_sink"
}

bt_sink_running() {
    timeout 5 pactl list sinks short 2>/dev/null | grep -q "bluez_sink.*RUNNING"
}

reset_audio() {
    echo "$(date): Resetting audio stack"
    # Kill mpv so it restarts fresh after reset
    pkill mpv 2>/dev/null
    sleep 1
    timeout 5 bluetoothctl disconnect "$BTADDR" 2>/dev/null
    sleep 2
    # Kill any stray PA processes and clean PID file, then restart via systemd
    pkill -9 pulseaudio 2>/dev/null
    sleep 1
    rm -f "/run/user/$(id -u)/pulse/pid"
    systemctl --user reset-failed pulseaudio.service 2>/dev/null
    systemctl --user restart pulseaudio.service
    sleep 3
    timeout 10 bluetoothctl connect "$BTADDR" 2>/dev/null
    sleep 8
}

ensure_bt() {
    if ! bt_connected; then
        timeout 10 bluetoothctl connect "$BTADDR" 2>/dev/null
        sleep 5
    fi

    if bt_connected && ! bt_sink_available; then
        reset_audio
    fi

    bt_connected && bt_sink_available
}

while true; do
    if ensure_bt; then
        # Play until mpv exits (stream drop, BT disconnect, etc.)
        mpv --no-video --quiet \
            -playlist "$STREAM" 2>/dev/null &
        MPV_PID=$!
        # Monitor: if sink disappears, kill mpv to trigger reconnect
        while kill -0 "$MPV_PID" 2>/dev/null; do
            sleep 30
            if ! bt_sink_running && ! bt_sink_available; then
                echo "$(date): Sink gone while mpv running, killing mpv"
                kill "$MPV_PID" 2>/dev/null
                break
            fi
        done
        wait "$MPV_PID" 2>/dev/null
        sleep 2
    else
        sleep "$RETRY_INTERVAL"
    fi
done
