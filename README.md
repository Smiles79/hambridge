# HamBridge

Ham Radio Recorder Bridge — Raspberry Pi daemon and Android companion app.

Press a button on your phone → query the radio's frequency via CAT → record RX audio → save a WAV file named `14.2250MHz_20260313_183045_EM72.wav` on your phone.

The radio's microphone, PTT, and front panel are completely unaffected.


## Installation

```bash
sudo git clone https://github.com/Smiles79/hambridge.git
```

'''bash
cd hambridge
'''

'''bash
cd pi
'''

'''bash
sudo bash install.sh
'''

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
