#!/usr/bin/env python3
# =============================================================================
#  hambridge.py
#  HamBridge — Ham Radio Recorder Bridge Daemon
#
#  Radio-agnostic. The Android app sends a set_radio command on connect
#  which tells this daemon which hamlib model, baud rate, and serial
#  parameters to use. rigctld is (re)started automatically.
#
#  UTC time and date always come from the phone via start_recording.
#  The Pi's own clock is never used for filenames.
# =============================================================================

import bluetooth
import socket
import json
import subprocess
import threading
import logging
import struct
import time
import os
import sys
import signal

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s'
)
log = logging.getLogger("hambridge")

# ── Defaults (overridden by set_radio from app) ───────────────────────────────
RIGCTLD_HOST = "127.0.0.1"
RIGCTLD_PORT = 4532

SAMPLE_RATE  = 48000
CHANNELS     = 1
SAMPLE_WIDTH = 2
CHUNK_SIZE   = 4096

# CAT device — always /dev/hambridge (set by udev rule at install time)
CAT_DEVICE = "/dev/hambridge"

# Current radio config — updated when app sends set_radio
_radio_config = {
    "radio_name":   "Unknown",
    "hamlib_model": "1",        # hamlib dummy rig as safe default
    "baud_rate":    9600,
    "stop_bits":    1,
    "write_delay":  0,
    "cat_timeout":  5,
}
_radio_lock    = threading.Lock()
_rigctld_proc  = None
_rigctld_lock  = threading.Lock()


# =============================================================================
#  rigctld management
# =============================================================================

def start_rigctld(config):
    """
    Starts rigctld with the parameters sent by the app.
    If rigctld is already running, kills it first then restarts.
    PTT is permanently disabled — this daemon never transmits.
    """
    global _rigctld_proc

    with _rigctld_lock:
        # Kill existing rigctld if running
        if _rigctld_proc and _rigctld_proc.poll() is None:
            log.info("Stopping existing rigctld...")
            _rigctld_proc.terminate()
            try:
                _rigctld_proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                _rigctld_proc.kill()

        cmd = [
            "rigctld",
            "-m", str(config["hamlib_model"]),
            "-r", CAT_DEVICE,
            "-s", str(config["baud_rate"]),
            f"--set-conf=serial_stopbits={config['stop_bits']}",
            "--set-conf=dtr_state=off",
            "--set-conf=rts_state=off",
            "--set-conf=ptt_type=None",   # safety — never transmit
        ]
        if config.get("write_delay", 0) > 0:
            cmd.append(f"--set-conf=write_delay={config['write_delay']}")

        log.info(f"Starting rigctld: {' '.join(cmd)}")
        _rigctld_proc = subprocess.Popen(
            cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        time.sleep(2)
        log.info(f"rigctld started for {config['radio_name']}")


# =============================================================================
#  Audio
# =============================================================================

def find_audio_device():
    """Finds the ALSA card number for the USB audio device (Digirig/DR-891)."""
    result = subprocess.run(["arecord", "-l"], capture_output=True, text=True)
    for line in result.stdout.splitlines():
        if "USB" in line.upper() and "card" in line:
            card_num = line.split("card ")[1].split(":")[0].strip()
            log.info(f"Found USB audio device: card {card_num}")
            return f"hw:{card_num},0"
    log.warning("No USB audio device found — falling back to hw:1,0")
    return "hw:1,0"


AUDIO_DEVICE = find_audio_device()


def stream_audio(client_sock, stop_event):
    """
    Streams raw PCM from arecord to the phone as length-prefixed frames.
    Sends a zero-length frame as end-of-stream sentinel when stopped.
    """
    proc = subprocess.Popen(
        [
            "arecord",
            "-D", AUDIO_DEVICE,
            "-f", "S16_LE",
            "-r", str(SAMPLE_RATE),
            "-c", str(CHANNELS),
            "--buffer-time=500000",
            "-t", "raw",
            "-"
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL
    )

    try:
        while not stop_event.is_set():
            chunk = proc.stdout.read(CHUNK_SIZE)
            if not chunk:
                break
            client_sock.sendall(struct.pack("<I", len(chunk)) + chunk)
    except (BrokenPipeError, OSError) as e:
        log.warning(f"Audio stream interrupted: {e}")
    finally:
        proc.terminate()
        proc.wait()
        try:
            client_sock.sendall(struct.pack("<I", 0))  # end sentinel
        except OSError:
            pass
        log.info("Audio stream ended")


# =============================================================================
#  CAT
# =============================================================================

def get_frequency(cat_timeout):
    """Queries rigctld for VFO-A frequency. Returns Hz as int."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(cat_timeout)
        s.connect((RIGCTLD_HOST, RIGCTLD_PORT))
        s.sendall(b"f\n")
        return int(s.recv(1024).decode().strip())


# =============================================================================
#  WAV header
# =============================================================================

def make_wav_header(sample_rate, channels, sample_width):
    """Builds a WAV header with zero data size — app fixes it on stop."""
    byte_rate   = sample_rate * channels * sample_width
    block_align = channels * sample_width
    header  = struct.pack("<4sI4s", b"RIFF", 36, b"WAVE")
    header += struct.pack("<4sIHHIIHH",
        b"fmt ", 16, 1, channels, sample_rate,
        byte_rate, block_align, sample_width * 8)
    header += struct.pack("<4sI", b"data", 0)
    return header


# =============================================================================
#  JSON helpers
# =============================================================================

def send_json(sock, data):
    sock.sendall((json.dumps(data) + "\n").encode())


def read_json_line(sock):
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
    Handles one connected phone. Supported actions:
        set_radio         — reconfigure rigctld for the selected radio
        start_recording   — query frequency, stream audio
        stop_recording    — stop stream
        ping              — health check
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
                    "message": "Invalid JSON"
                })
                continue

            action = cmd.get("action", "")

            # ── set_radio ─────────────────────────────────────────────────
            if action == "set_radio":
                with _radio_lock:
                    _radio_config.update({
                        "radio_name":   cmd.get("radio_name", "Unknown"),
                        "hamlib_model": cmd.get("hamlib_model", "1"),
                        "baud_rate":    int(cmd.get("baud_rate", 9600)),
                        "stop_bits":    int(cmd.get("stop_bits", 1)),
                        "write_delay":  int(cmd.get("write_delay", 0)),
                        "cat_timeout":  int(cmd.get("cat_timeout", 5)),
                    })
                    config = dict(_radio_config)

                # Restart rigctld with new radio parameters
                t = threading.Thread(
                    target=start_rigctld, args=(config,), daemon=True)
                t.start()

                send_json(client_sock, {
                    "status":     "radio_set",
                    "radio_name": config["radio_name"]
                })
                log.info(f"Radio set to: {config['radio_name']}")

            # ── ping ──────────────────────────────────────────────────────
            elif action == "ping":
                with _radio_lock:
                    radio_name = _radio_config["radio_name"]
                send_json(client_sock, {
                    "status":  "ok",
                    "message": "pong",
                    "radio":   radio_name
                })

            # ── start_recording ───────────────────────────────────────────
            elif action == "start_recording":
                if recording:
                    send_json(client_sock, {
                        "status":  "error",
                        "message": "Already recording"
                    })
                    continue

                grid     = cmd.get("grid", "UNKNOWN").upper()

                # UTC time and date ALWAYS come from the phone
                # The Pi never uses its own clock for filenames
                utc_str  = cmd.get("utc_time", "")
                if not utc_str:
                    send_json(client_sock, {
                        "status":  "error",
                        "message": "utc_time missing from start_recording command"
                    })
                    continue

                # Parse ISO 8601 UTC from phone: "2026-03-13T18:30:45.123Z"
                from datetime import datetime, timezone
                utc_now  = datetime.fromisoformat(
                    utc_str.replace("Z", "+00:00")
                ).astimezone(timezone.utc)

                date_str = utc_now.strftime("%Y%m%d")
                time_str = utc_now.strftime("%H%M%S")

                with _radio_lock:
                    cat_timeout = _radio_config["cat_timeout"]

                log.info("Querying frequency...")
                try:
                    freq_hz = get_frequency(cat_timeout)
                except (socket.timeout, OSError) as e:
                    send_json(client_sock, {
                        "status":  "error",
                        "message": f"CAT query failed: {e}"
                    })
                    continue

                freq_str = f"{freq_hz / 1_000_000:.4f}MHz"
                filename = f"{freq_str}_{date_str}_{time_str}_{grid}.wav"

                wav_header = make_wav_header(SAMPLE_RATE, CHANNELS, SAMPLE_WIDTH)
                send_json(client_sock, {
                    "status":         "recording",
                    "filename":       filename,
                    "freq_hz":        freq_hz,
                    "freq_mhz":       round(freq_hz / 1_000_000, 4),
                    "utc":            utc_now.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "grid":           grid,
                    "sample_rate":    SAMPLE_RATE,
                    "channels":       CHANNELS,
                    "sample_width":   SAMPLE_WIDTH,
                    "wav_header_hex": wav_header.hex()
                })

                stop_event   = threading.Event()
                audio_thread = threading.Thread(
                    target=stream_audio,
                    args=(client_sock, stop_event),
                    daemon=True
                )
                audio_thread.start()
                recording = True
                log.info(f"Recording started: {filename}")

            # ── stop_recording ────────────────────────────────────────────
            elif action == "stop_recording":
                if not recording:
                    send_json(client_sock, {
                        "status":  "error",
                        "message": "Not recording"
                    })
                    continue

                stop_event.set()
                audio_thread.join(timeout=5)
                recording    = False
                stop_event   = None
                audio_thread = None
                send_json(client_sock, {"status": "stopped"})
                log.info("Recording stopped")

            else:
                send_json(client_sock, {
                    "status":  "error",
                    "message": f"Unknown action: '{action}'"
                })

    except ConnectionResetError:
        log.info(f"Phone disconnected: {addr}")
    except Exception as e:
        log.error(f"Error handling {addr}: {e}")
    finally:
        if stop_event:
            stop_event.set()
        client_sock.close()


# =============================================================================
#  Main
# =============================================================================

def main():
    log.info("HamBridge starting — waiting for app to send radio config")
    log.info(f"CAT device: {CAT_DEVICE}")
    log.info(f"Audio device: {AUDIO_DEVICE}")

    server_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
    server_sock.bind(("", bluetooth.PORT_ANY))
    server_sock.listen(1)

    bluetooth.advertise_service(
        server_sock,
        "HamBridge",
        service_id=bluetooth.SERIAL_PORT_CLASS,
        service_classes=[bluetooth.SERIAL_PORT_CLASS],
        profiles=[bluetooth.SERIAL_PORT_PROFILE]
    )

    port = server_sock.getsockname()[1]
    log.info(f"Listening on RFCOMM port {port}")

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
