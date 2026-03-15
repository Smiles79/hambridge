import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

// ── Radio models ──────────────────────────────────────────────────────────────

class RadioModel {
  final String name;
  final String hamlibModel;
  final int baudRate;
  final int stopBits;
  final int writeDelay;
  final int catTimeout;

  const RadioModel({
    required this.name,
    required this.hamlibModel,
    required this.baudRate,
    required this.stopBits,
    required this.writeDelay,
    required this.catTimeout,
  });
}

const List<RadioModel> kSupportedRadios = [
  RadioModel(
    name: 'Yaesu FT-891',
    hamlibModel: '136',
    baudRate: 38400,
    stopBits: 1,
    writeDelay: 0,
    catTimeout: 3,
  ),
  RadioModel(
    name: 'Yaesu FT-747GX',
    hamlibModel: '105',
    baudRate: 4800,
    stopBits: 2,
    writeDelay: 50,
    catTimeout: 5,
  ),
];

enum ConnectionState { disconnected, connecting, connected }
enum RecordingState  { idle, recording }

class BridgeService extends ChangeNotifier {
  final FlutterBlueClassic _ble = FlutterBlueClassic();
  BluetoothConnection? _connection;
  StreamSubscription? _inputSub;

  ConnectionState connectionState = ConnectionState.disconnected;
  RecordingState  recordingState  = RecordingState.idle;

  String?     connectedDeviceName;
  String?     currentFilename;
  double?     currentFreqMhz;
  String?     lastSavedPath;
  String?     statusMessage;
  String?     errorMessage;
  String?     saveFolder;
  RadioModel  selectedRadio = kSupportedRadios.first;
  List<String> recordings   = [];

  IOSink? _wavSink;
  File?   _wavFile;
  int     _audioByteCount = 0;
  int     _sampleRate     = 48000;
  int     _channels       = 1;
  int     _sampleWidth    = 2;

  final List<int> _audioBuffer = [];
  final List<int> _lineBuffer  = [];
  bool _expectingAudio = false;
  bool _streamingAudio = false;

  Future<void> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    saveFolder = prefs.getString('save_folder');
    final radioName = prefs.getString('radio_name');
    if (radioName != null) {
      selectedRadio = kSupportedRadios.firstWhere(
            (r) => r.name == radioName,
        orElse: () => kSupportedRadios.first,
      );
    }
    notifyListeners();
  }

  Future<void> setRadio(RadioModel radio) async {
    selectedRadio = radio;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('radio_name', radio.name);
    notifyListeners();
    if (connectionState == ConnectionState.connected) {
      _sendRadioConfig();
    }
  }

  Future<List<BluetoothDevice>> getPairedDevices() async {
    return await _ble.bondedDevices ?? [];
  }

  Future<void> connect(BluetoothDevice device) async {
    try {
      connectionState = ConnectionState.connecting;
      statusMessage   = 'Connecting to ${device.name}…';
      errorMessage    = null;
      notifyListeners();

      _connection         = await _ble.connect(device.address);
      connectedDeviceName = device.name;
      connectionState     = ConnectionState.connected;
      statusMessage       = 'Connected to ${device.name}';
      notifyListeners();

      _inputSub = _connection!.input!.listen(
        _onData,
        onDone:  _onDisconnected,
        onError: (_) => _onDisconnected(),
      );

      // Tell Pi which radio on connect
      _sendRadioConfig();

    } catch (e) {
      connectionState = ConnectionState.disconnected;
      errorMessage    = 'Connection failed: $e';
      statusMessage   = null;
      notifyListeners();
    }
  }

  void disconnect() {
    _inputSub?.cancel();
    _connection?.dispose();
    _connection         = null;
    connectedDeviceName = null;
    connectionState     = ConnectionState.disconnected;
    recordingState      = RecordingState.idle;
    _expectingAudio     = false;
    _streamingAudio     = false;
    statusMessage       = 'Disconnected';
    notifyListeners();
  }

  /// grid and utcNow come from GpsService and DateTime.now().toUtc()
  /// in the UI — the Pi never decides time or location
  Future<void> toggleRecording(String grid, DateTime utcNow) async {
    if (recordingState == RecordingState.idle) {
      await _startRecording(grid, utcNow);
    } else {
      await _stopRecording();
    }
  }

  void _sendRadioConfig() {
    _send({
      'action':       'set_radio',
      'hamlib_model': selectedRadio.hamlibModel,
      'baud_rate':    selectedRadio.baudRate,
      'stop_bits':    selectedRadio.stopBits,
      'write_delay':  selectedRadio.writeDelay,
      'cat_timeout':  selectedRadio.catTimeout,
      'radio_name':   selectedRadio.name,
    });
  }

  void _send(Map<String, dynamic> cmd) {
    if (_connection == null) return;
    _connection!.output.add(
        Uint8List.fromList(utf8.encode('${jsonEncode(cmd)}\n'))
    );
  }

  void _onData(Uint8List data) {
    if (_expectingAudio) {
      _handleAudioBytes(data);
    } else {
      for (final byte in data) {
        if (byte == 0x0A) {
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
      final msg    = jsonDecode(line) as Map<String, dynamic>;
      final status = msg['status'] as String? ?? '';

      if (status == 'recording') {
        currentFilename = msg['filename'] as String?;
        currentFreqMhz  = (msg['freq_mhz'] as num?)?.toDouble();
        _sampleRate     = (msg['sample_rate']  as num?)?.toInt() ?? 48000;
        _channels       = (msg['channels']     as num?)?.toInt() ?? 1;
        _sampleWidth    = (msg['sample_width'] as num?)?.toInt() ?? 2;

        _openWavFile(currentFilename!, msg['wav_header_hex'] as String? ?? '');
        recordingState  = RecordingState.recording;
        statusMessage   = 'Recording ${currentFreqMhz?.toStringAsFixed(4)} MHz';
        _expectingAudio = true;
        _streamingAudio = true;
        _audioBuffer.clear();
        notifyListeners();

      } else if (status == 'stopped') {
        _finaliseWav();
        recordingState  = RecordingState.idle;
        statusMessage   = 'Saved: $currentFilename';
        _expectingAudio = false;
        _streamingAudio = false;
        notifyListeners();

      } else if (status == 'radio_set') {
        statusMessage = 'Radio configured: ${msg['radio_name']}';
        notifyListeners();

      } else if (status == 'error') {
        errorMessage = msg['message'] as String?;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('JSON parse: $e');
    }
  }

  void _handleAudioBytes(Uint8List data) {
    _audioBuffer.addAll(data);
    while (_audioBuffer.length >= 4) {
      final len = ByteData.sublistView(
          Uint8List.fromList(_audioBuffer.sublist(0, 4))
      ).getUint32(0, Endian.little);

      if (len == 0) {
        _audioBuffer.clear();
        _expectingAudio = false;
        _streamingAudio = false;
        return;
      }
      if (_audioBuffer.length < 4 + len) break;

      final chunk = _audioBuffer.sublist(4, 4 + len);
      _audioBuffer.removeRange(0, 4 + len);
      _wavSink?.add(Uint8List.fromList(chunk));
      _audioByteCount += chunk.length;
    }
  }

  void _openWavFile(String filename, String headerHex) {
    if (saveFolder == null) return;
    final path    = p.join(saveFolder!, filename);
    _wavFile      = File(path);
    _wavSink      = _wavFile!.openWrite();
    _audioByteCount = 0;
    lastSavedPath = path;
    if (headerHex.isNotEmpty) _wavSink!.add(_hexToBytes(headerHex));
  }

  Future<void> _finaliseWav() async {
    await _wavSink?.flush();
    await _wavSink?.close();
    _wavSink = null;

    if (_wavFile != null && await _wavFile!.exists()) {
      final raf      = await _wavFile!.open(mode: FileMode.writeOnlyAppend);
      final fileSize = await _wavFile!.length();
      await raf.setPosition(4);
      await raf.writeFrom(_int32LE(fileSize - 8));
      await raf.setPosition(40);
      await raf.writeFrom(_int32LE(_audioByteCount));
      await raf.close();
      if (!recordings.contains(currentFilename)) {
        recordings.insert(0, currentFilename!);
      }
    }
    _wavFile = null;
  }

  Future<void> _startRecording(String grid, DateTime utcNow) async {
    if (_connection == null) { errorMessage = 'Not connected'; notifyListeners(); return; }
    if (saveFolder == null)  { errorMessage = 'No save folder'; notifyListeners(); return; }
    errorMessage  = null;
    statusMessage = 'Querying frequency…';
    notifyListeners();
    _send({
      'action':   'start_recording',
      'grid':     grid.toUpperCase(),
      'utc_time': utcNow.toUtc().toIso8601String(), // phone provides UTC
    });
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

  Uint8List _hexToBytes(String hex) {
    final r = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < r.length; i++) {
      r[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return r;
  }

  List<int> _int32LE(int v) {
    final bd = ByteData(4);
    bd.setUint32(0, v, Endian.little);
    return bd.buffer.asUint8List();
  }

  @override
  void dispose() {
    _inputSub?.cancel();
    _connection?.dispose();
    super.dispose();
  }
}