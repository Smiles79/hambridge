# HamBridge

Ham Radio Recorder Bridge — Raspberry Pi daemon and Android companion app.

Press a button on your phone → query the radio's frequency via CAT → record RX audio → save a WAV file named `14.2250MHz_20260313_183045_EM72.wav` on your phone.

The radio's microphone, PTT, and front panel are completely unaffected.


## Installation

```bash
curl -sSL https://github.com/Smiles79/hambridge/archive/main.tar.gz | tar -xz -C /tmp && bash /tmp/hambridge-main/install.sh
```

## Repository Structure

```
hambridge/
├── install.sh              ← entry point — run this
├── hambridge.py            ← bridge daemon (Python)
├── diagnose.sh             ← run if anything isn't working
├── uninstall.sh            ← clean removal
└── lib/
    ├── config.sh           ← shared HB_ variables and hb_ helpers
    ├── packages.sh         ← apt package installation
    ├── udev.sh             ← stable CAT port alias (/dev/hambridge)
    ├── daemon.sh           ← places hambridge.py and settings file
    ├── systemd.sh          ← hambridge.service creation and management
    └── bluetooth.sh        ← BlueZ permanent discoverability config
```

## After Installation

Files installed to `~/hambridge/`:
- `hambridge.py` — the daemon (do not edit directly)
- `hambridge_settings.py` — **edit this** to change radio parameters
- `diagnose.sh` — run any time something isn't working
- `uninstall.sh` — clean removal

### Changing radio settings

```bash
nano ~/hambridge/hambridge_settings.py
sudo systemctl restart hambridge
```

### Useful commands

```bash
sudo systemctl status hambridge     # service status
sudo journalctl -u hambridge -f     # live logs
bash ~/hambridge/diagnose.sh        # full system check
```

## Android App

See the `android/` directory. Built with Flutter.

```bash
cd android
flutter pub get
flutter run
```

## Protocol

```
Phone → Pi:   {"action":"start_recording","grid":"EM72"}\n
Pi → Phone:   {"status":"recording","filename":"14.2250MHz_20260313_183045_EM72.wav",...}\n
Pi → Phone:   [4-byte LE length][PCM bytes] × N
Pi → Phone:   [0x00000000]  ← end sentinel
Phone → Pi:   {"action":"stop_recording"}\n
Pi → Phone:   {"status":"stopped"}\n
```

Audio: 48 kHz, 16-bit, mono PCM WAV.
