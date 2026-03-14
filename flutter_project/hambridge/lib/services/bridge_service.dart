import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:path/path.dart' as p;

enum ConnectionState { disconnected, connecting, connected }

enum RecordingState { idle, recording }

class BridgeService extends ChangeNotifier {
  // ── Bluetooth ──────────────────────────────────────────
  final FlutterBlueClassic _ble = FlutterBlueClassic();
  BluetoothConnection? _connection;
  StreamSubscription? _inputSub;

  ConnectionState connectionState = ConnectionState.disconnected;
  RecordingState recordingState = RecordingState.idle;

  // ── State visible to UI ────────────────────────────────
  String? connectedDeviceName;
  String? currentFilename;
  double? currentFreqMhz;
  String? lastSavedPath;
  String? statusMessage;
  String? errorMessage;
  String? saveFolder;          // chosen by user from settings
  List<String> recordings = [];

  // ── Internal recording state ───────────────────────────
  IOSink? _wavSink;
  File? _wavFile;
  int _audioByteCount = 0;
  int _sampleRate = 48000;
  int _channels = 1;
  int _sampleWidth = 2;

  // Leftover bytes from previous chunks (for the 4-byte length framing)
  final List<int> _audioBuffer = [];
  bool _streamingAudio = false;

  // ── Line buffer for JSON responses ────────────────────
  final List<int> _lineBuffer = [];
  bool _expectingAudio = false;

  // ── Public API ─────────────────────────────────────────

  Future<List<BluetoothDevice>> getPairedDevices() async {
    return await _ble.bondedDevices ?? [];
  }

  Future<void> connect(BluetoothDevice device) async {
    try {
      connectionState = ConnectionState.connecting;
      statusMessage = 'Connecting to ${device.name}…';
      errorMessage = null;
      notifyListeners();

      _connection = await _ble.connect(device.address);
      connectedDeviceName = device.name;
      connectionState = ConnectionState.connected;
      statusMessage = 'Connected to ${device.name}';
      notifyListeners();

      _inputSub = _connection!.input!.listen(
        _onData,
        onDone: _onDisconnected,
        onError: (e) => _onDisconnected(),
      );
    } catch (e) {
      connectionState = ConnectionState.disconnected;
      errorMessage = 'Connection failed: $e';
      statusMessage = null;
      notifyListeners();
    }
  }

  void disconnect() {
    _inputSub?.cancel();
    _connection?.dispose();
    _connection = null;
    connectedDeviceName = null;
    connectionState = ConnectionState.disconnected;
    recordingState = RecordingState.idle;
    _expectingAudio = false;
    _streamingAudio = false;
    statusMessage = 'Disconnected';
    notifyListeners();
  }

  Future<void> toggleRecording(String grid) async {
    if (recordingState == RecordingState.idle) {
      await _startRecording(grid);
    } else {
      await _stopRecording();
    }
  }

  // ── Private: send / receive ────────────────────────────

  void _send(Map<String, dynamic> cmd) {
    if (_connection == null) return;
    final bytes = utf8.encode('${jsonEncode(cmd)}\n');
    _connection!.output.add(Uint8List.fromList(bytes));
  }

  /// All incoming bytes come here — may be JSON lines or binary audio frames
  void _onData(Uint8List data) {
    if (_expectingAudio) {
      _handleAudioBytes(data);
    } else {
      // Accumulate until we have a complete JSON line
      for (final byte in data) {
        if (byte == 0x0A) {
          // newline — process line
          final line = utf8.decode(_lineBuffer, allowMalformed: true).trim();
          _lineBuffer.clear();
          if (line.isNotEmpty) _handleJsonLine(line);
        } else {
          _lineBuffer.add(byte);
        }
      }
    }
  }

  void _handleJsonLine(String line) {
    try {
      final msg = jsonDecode(line) as Map<String, dynamic>;
      final status = msg['status'] as String? ?? '';

      if (status == 'recording') {
        // Pi confirmed recording started — open WAV file and switch to audio mode
        currentFilename = msg['filename'] as String?;
        currentFreqMhz = (msg['freq_mhz'] as num?)?.toDouble();
        _sampleRate   = (msg['sample_rate'] as num?)?.toInt() ?? 48000;
        _channels     = (msg['channels'] as num?)?.toInt() ?? 1;
        _sampleWidth  = (msg['sample_width'] as num?)?.toInt() ?? 2;

        final headerHex = msg['wav_header_hex'] as String? ?? '';
        _openWavFile(currentFilename!, headerHex);

        recordingState = RecordingState.recording;
        statusMessage = 'Recording ${currentFreqMhz?.toStringAsFixed(4)} MHz';
        _expectingAudio = true;
        _streamingAudio = true;
        _audioBuffer.clear();
        notifyListeners();

      } else if (status == 'stopped') {
        _finaliseWav();
        recordingState = RecordingState.idle;
        statusMessage = 'Saved: $currentFilename';
        _expectingAudio = false;
        _streamingAudio = false;
        notifyListeners();

      } else if (status == 'error') {
        errorMessage = msg['message'] as String? ?? 'Unknown error';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('JSON parse error: $e  line=$line');
    }
  }

  /// Process incoming framed audio: [4-byte LE length][PCM bytes]
  void _handleAudioBytes(Uint8List data) {
    _audioBuffer.addAll(data);

    while (_audioBuffer.length >= 4) {
      // Peek at length prefix
      final len = ByteData.sublistView(
        Uint8List.fromList(_audioBuffer.sublist(0, 4))
      ).getUint32(0, Endian.little);

      if (len == 0) {
        // End-of-stream sentinel from Pi
        _audioBuffer.clear();
        _expectingAudio = false;
        _streamingAudio = false;
        // Pi will send the stopped JSON next — switch back to JSON mode
        return;
      }

      if (_audioBuffer.length < 4 + len) {
        // Haven't received the full chunk yet
        break;
      }

      final chunk = _audioBuffer.sublist(4, 4 + len);
      _audioBuffer.removeRange(0, 4 + len);

      _wavSink?.add(Uint8List.fromList(chunk));
      _audioByteCount += chunk.length;
    }
  }

  // ── WAV file handling ──────────────────────────────────

  void _openWavFile(String filename, String headerHex) {
    if (saveFolder == null) return;

    final path = p.join(saveFolder!, filename);
    _wavFile = File(path);
    _wavSink = _wavFile!.openWrite();
    _audioByteCount = 0;

    // Write the WAV header bytes sent by Pi
    if (headerHex.isNotEmpty) {
      final headerBytes = _hexToBytes(headerHex);
      _wavSink!.add(headerBytes);
    }

    lastSavedPath = path;
  }

  Future<void> _finaliseWav() async {
    await _wavSink?.flush();
    await _wavSink?.close();
    _wavSink = null;

    // Fix up WAV header with real byte counts
    if (_wavFile != null && await _wavFile!.exists()) {
      final raf = await _wavFile!.open(mode: FileMode.writeOnlyAppend);
      // RIFF chunk size = file size - 8
      final fileSize = await _wavFile!.length();
      await raf.setPosition(4);
      await raf.writeFrom(_int32LE(fileSize - 8));
      // data chunk size = audio bytes
      await raf.setPosition(40);
      await raf.writeFrom(_int32LE(_audioByteCount));
      await raf.close();

      if (!recordings.contains(currentFilename)) {
        recordings.insert(0, currentFilename!);
      }
    }
    _wavFile = null;
  }

  Future<void> _startRecording(String grid) async {
    if (_connection == null) {
      errorMessage = 'Not connected';
      notifyListeners();
      return;
    }
    if (saveFolder == null) {
      errorMessage = 'No save folder selected';
      notifyListeners();
      return;
    }
    errorMessage = null;
    statusMessage = 'Querying frequency…';
    notifyListeners();
    _send({'action': 'start_recording', 'grid': grid.toUpperCase()});
  }

  Future<void> _stopRecording() async {
    _send({'action': 'stop_recording'});
    statusMessage = 'Stopping…';
    notifyListeners();
  }

  void _onDisconnected() {
    if (_streamingAudio) _finaliseWav();
    disconnect();
  }

  // ── Helpers ────────────────────────────────────────────

  Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  List<int> _int32LE(int value) {
    final bd = ByteData(4);
    bd.setUint32(0, value, Endian.little);
    return bd.buffer.asUint8List();
  }

  @override
  void dispose() {
    _inputSub?.cancel();
    _connection?.dispose();
    super.dispose();
  }
}
