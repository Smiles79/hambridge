#!/usr/bin/env python3
# =============================================================================
#  hambridge.py
#  HamBridge — Ham Radio Recorder Bridge Daemon
#
#  Responsibilities:
#    - Starts rigctld (hamlib) to talk to the radio via CAT
#    - Listens for Bluetooth RFCOMM connections from the Android app
#    - On "start_recording": queries frequency via CAT, begins streaming
#      raw PCM audio from the Digirig/DR-891 USB audio device
#    - Audio is framed as [4-byte LE length][PCM bytes] for the app
#    - On "stop_recording": stops audio stream, sends end sentinel
#
#  All radio-specific settings are in hambridge_settings.py in the
#  same directory. Edit that file to change radio parameters.
#  After editing: sudo systemctl restart hambridge
# =============================================================================

import bluetooth
import socket
import json
import datetime
import subprocess
import threading
import logging
import struct
import time
import os
import sys

# ── Load settings ─────────────────────────────────────────────────────────────
# hambridge_settings.py lives in the same directory as this script
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from hambridge_settings import (
        HAMLIB_MODEL, BAUD_RATE, STOP_BITS, WRITE_DELAY,
        CAT_DEVICE, CAT_TIMEOUT, BT_SERVICE_NAME,
        SAMPLE_RATE, CHANNELS, SAMPLE_WIDTH, CHUNK_SIZE,
        RADIO_MODEL
    )
except ImportError:
    print("ERROR: hambridge_settings.py not found.")
    print("Re-run the installer or create hambridge_settings.py manually.")
    sys.exit(1)

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s'
)
log = logging.getLogger("hambridge")

# ── rigctld connection ────────────────────────────────────────────────────────
RIGCTLD_HOST = "127.0.0.1"
RIGCTLD_PORT = 4532


# =============================================================================
#  Audio device detection
# =============================================================================

def find_audio_device():
    """
    Finds the ALSA card number for the Digirig / DR-891 USB audio device.
    Returns a device string like "hw:1,0".
    Falls back to "hw:1,0" if no USB audio device is found.
    """
    result = subprocess.run(
        ["arecord", "-l"],
        capture_output=True, text=True
    )
    for line in result.stdout.splitlines():
        if "USB" in line.upper() and "card" in line:
            card_num = line.split("card ")[1].split(":")[0].strip()
            log.info(f"Found USB audio device: card {card_num}")
            return f"hw:{card_num},0"
    log.warning("No USB audio device found — falling back to hw:1,0")
    return "hw:1,0"


AUDIO_DEVICE = find_audio_device()


# =============================================================================
#  CAT control
# =============================================================================

def get_frequency():
    """
    Sends a frequency query to rigctld and returns the VFO-A frequency in Hz.
    Raises socket.timeout if the radio doesn't respond in time (e.g. FT-747GX
    takes ~1 second at 4800 baud — CAT_TIMEOUT is set generously in settings).
    """
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(CAT_TIMEOUT)
        s.connect((RIGCTLD_HOST, RIGCTLD_PORT))
        s.sendall(b"f\n")
        response = s.recv(1024).decode().strip()
        return int(response)


# =============================================================================
#  WAV header
# =============================================================================

def make_wav_header(sample_rate, channels, sample_width, num_samples=0):
    """
    Builds a standard WAV file header.
    num_samples=0 produces a placeholder header — the Android app fixes up
    the byte counts when recording stops (see bridge_service.dart).
    """
    byte_rate   = sample_rate * channels * sample_width
    block_align = channels * sample_width
    data_size   = num_samples * channels * sample_width
    chunk_size  = 36 + data_size

    header  = struct.pack("<4sI4s", b"RIFF", chunk_size, b"WAVE")
    header += struct.pack("<4sIHHIIHH",
        b"fmt ", 16,
        1,              # PCM format
        channels,
        sample_rate,
        byte_rate,
        block_align,
        sample_width * 8
    )
    header += struct.pack("<4sI", b"data", data_size)
    return header


# =============================================================================
#  Audio streaming
# =============================================================================

def stream_audio(client_sock, stop_event):
    """
    Launches arecord, reads raw PCM in chunks, and sends each chunk to the
    phone as a length-prefixed binary frame:
        [4-byte little-endian length][PCM bytes]

    When stop_event is set (by stop_recording command), terminates arecord
    and sends a zero-length frame as an end-of-stream sentinel so the app
    knows to finalise the WAV file.
    """
    proc = subprocess.Popen(
        [
            "arecord",
            "-D", AUDIO_DEVICE,
            "-f", "S16_LE",
            "-r", str(SAMPLE_RATE),
            "-c", str(CHANNELS),
            "--buffer-time=500000",     # 500ms ring buffer — reduces dropouts
            "-t", "raw",                # raw PCM, no WAV header from arecord
            "-"                         # write to stdout
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL
    )

    try:
        while not stop_event.is_set():
            chunk = proc.stdout.read(CHUNK_SIZE)
            if not chunk:
                break
            # Length-prefix frame so the app knows exactly how many bytes follow
            frame = struct.pack("<I", len(chunk)) + chunk
            client_sock.sendall(frame)

    except (BrokenPipeError, OSError) as e:
        log.warning(f"Audio stream interrupted: {e}")

    finally:
        proc.terminate()
        proc.wait()
        # Zero-length frame = end of stream
        try:
            client_sock.sendall(struct.pack("<I", 0))
        except OSError:
            pass
        log.info("Audio stream ended")


# =============================================================================
#  JSON helpers
# =============================================================================

def send_json(sock, data):
    """Sends a newline-terminated JSON message to the phone."""
    sock.sendall((json.dumps(data) + "\n").encode())


def read_json_line(sock):
    """
    Reads bytes from the socket until a newline, then parses as JSON.
    Returns the parsed dict, or raises ConnectionResetError on disconnect.
    """
    raw = b""
    while not raw.endswith(b"\n"):
        chunk = sock.recv(256)
        if not chunk:
            raise ConnectionResetError("Client disconnected")
        raw += chunk
    return json.loads(raw.decode().strip())


# =============================================================================
#  Client handler
# =============================================================================

def handle_client(client_sock, addr):
    """
    Handles all communication with one connected phone.
    Runs in its own thread per connection.

    Supported actions (sent as JSON from the app):
        ping              — health check, returns pong
        start_recording   — queries frequency, sends metadata + WAV header,
                            begins streaming audio frames
        stop_recording    — stops audio stream, sends stopped confirmation
    """
    log.info(f"Phone connected: {addr}")

    stop_event   = None
    audio_thread = None
    recording    = False

    try:
        while True:
            try:
                cmd = read_json_line(client_sock)
            except json.JSONDecodeError:
                send_json(client_sock, {
                    "status": "error",
                    "message": "Invalid JSON — check app is sending newline-terminated JSON"
                })
                continue

            action = cmd.get("action", "")

            # ── ping ──────────────────────────────────────────────────────────
            if action == "ping":
                send_json(client_sock, {
                    "status": "ok",
                    "message": "pong",
                    "radio": RADIO_MODEL
                })

            # ── start_recording ───────────────────────────────────────────────
            elif action == "start_recording":
                if recording:
                    send_json(client_sock, {
                        "status": "error",
                        "message": "Already recording — send stop_recording first"
                    })
                    continue

                grid    = cmd.get("grid", "UNKNOWN").upper()
                utc_now = datetime.datetime.utcnow()

                log.info(f"Querying frequency from {RADIO_MODEL}...")
                try:
                    freq_hz = get_frequency()
                except (socket.timeout, OSError) as e:
                    send_json(client_sock, {
                        "status": "error",
                        "message": f"CAT frequency query failed: {e}"
                    })
                    continue

                # Build filename: 14.2250MHz_20260313_183045_EM72.wav
                freq_str = f"{freq_hz / 1_000_000:.4f}MHz"
                date_str = utc_now.strftime("%Y%m%d")
                time_str = utc_now.strftime("%H%M%S")
                filename = f"{freq_str}_{date_str}_{time_str}_{grid}.wav"

                # Send metadata and WAV header to app before streaming starts.
                # The app writes the header first, then appends incoming audio
                # frames, then fixes up the byte counts in the header on stop.
                wav_header = make_wav_header(SAMPLE_RATE, CHANNELS, SAMPLE_WIDTH)
                send_json(client_sock, {
                    "status":          "recording",
                    "filename":        filename,
                    "freq_hz":         freq_hz,
                    "freq_mhz":        round(freq_hz / 1_000_000, 4),
                    "utc":             utc_now.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "grid":            grid,
                    "sample_rate":     SAMPLE_RATE,
                    "channels":        CHANNELS,
                    "sample_width":    SAMPLE_WIDTH,
                    "wav_header_hex":  wav_header.hex()
                })

                # Start audio streaming in background thread
                stop_event   = threading.Event()
                audio_thread = threading.Thread(
                    target=stream_audio,
                    args=(client_sock, stop_event),
                    daemon=True
                )
                audio_thread.start()
                recording = True
                log.info(f"Recording started: {filename}")

            # ── stop_recording ────────────────────────────────────────────────
            elif action == "stop_recording":
                if not recording:
                    send_json(client_sock, {
                        "status": "error",
                        "message": "Not currently recording"
                    })
                    continue

                stop_event.set()
                audio_thread.join(timeout=5)
                recording    = False
                stop_event   = None
                audio_thread = None

                send_json(client_sock, {"status": "stopped"})
                log.info("Recording stopped")

            # ── unknown ───────────────────────────────────────────────────────
            else:
                send_json(client_sock, {
                    "status": "error",
                    "message": f"Unknown action: '{action}'"
                })

    except ConnectionResetError:
        log.info(f"Phone disconnected: {addr}")
    except Exception as e:
        log.error(f"Unexpected error handling {addr}: {e}")
    finally:
        if stop_event:
            stop_event.set()
        client_sock.close()
        log.info(f"Connection closed: {addr}")


# =============================================================================
#  rigctld startup
# =============================================================================

def start_rigctld():
    """
    Starts the hamlib rigctld daemon as a background process.
    rigctld translates generic hamlib commands into radio-specific CAT.

    Key flags:
        ptt_type=None   — disables all PTT methods (radio cannot be keyed)
        rts_state=off   — RTS line never asserted (prevents accidental PTT)
        dtr_state=off   — DTR line never asserted
    """
    cmd = [
        "rigctld",
        "-m", str(HAMLIB_MODEL),
        "-r", CAT_DEVICE,
        "-s", str(BAUD_RATE),
        f"--set-conf=serial_stopbits={STOP_BITS}",
        "--set-conf=dtr_state=off",
        "--set-conf=rts_state=off",
        "--set-conf=ptt_type=None",   # safety — this daemon never transmits
    ]
    if WRITE_DELAY > 0:
        cmd.append(f"--set-conf=write_delay={WRITE_DELAY}")

    log.info(f"Starting rigctld for {RADIO_MODEL} at {BAUD_RATE} baud...")
    log.info(f"Command: {' '.join(cmd)}")

    subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(3)   # allow rigctld time to open the serial port
    log.info("rigctld started")


# =============================================================================
#  Bluetooth RFCOMM server
# =============================================================================

def start_bluetooth_server():
    """
    Creates a Bluetooth RFCOMM server socket and advertises it as a
    Serial Port Profile (SPP) service. The Android app discovers and
    connects to this service by name (BT_SERVICE_NAME).

    Accepts one connection at a time in a thread so multiple reconnections
    work correctly without restarting the daemon.
    """
    server_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
    server_sock.bind(("", bluetooth.PORT_ANY))
    server_sock.listen(1)

    bluetooth.advertise_service(
        server_sock,
        BT_SERVICE_NAME,
        service_id=bluetooth.SERIAL_PORT_CLASS,
        service_classes=[bluetooth.SERIAL_PORT_CLASS],
        profiles=[bluetooth.SERIAL_PORT_PROFILE]
    )

    port = server_sock.getsockname()[1]
    log.info(f"HamBridge ready — Bluetooth RFCOMM port {port}")
    log.info(f"Advertising as: {BT_SERVICE_NAME}")
    log.info(f"Radio: {RADIO_MODEL} | Audio: {AUDIO_DEVICE}")

    return server_sock


# =============================================================================
#  Main
# =============================================================================

def main():
    start_rigctld()
    server_sock = start_bluetooth_server()

    while True:
        log.info("Waiting for phone connection...")
        client_sock, addr = server_sock.accept()
        t = threading.Thread(
            target=handle_client,
            args=(client_sock, addr),
            daemon=True
        )
        t.start()


if __name__ == "__main__":
    main()
