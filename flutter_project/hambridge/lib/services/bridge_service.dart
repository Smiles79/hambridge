import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

// ── Radio model ───────────────────────────────────────────────────────────────

class RadioModel {
  final String id;          // hamlib model number e.g. "136"
  final String mfg;         // manufacturer e.g. "Yaesu"
  final String name;        // full name e.g. "Yaesu FT-891"
  final int baudRate;       // CAT baud rate
  final int stopBits;       // serial stop bits
  final int writeDelay;     // ms between bytes
  final int catTimeout;     // seconds to wait for CAT response

  const RadioModel({
    required this.id,
    required this.mfg,
    required this.name,
    this.baudRate   = 38400,
    this.stopBits   = 1,
    this.writeDelay = 0,
    this.catTimeout = 5,
  });

  RadioModel copyWith({
    int? baudRate,
    int? stopBits,
    int? writeDelay,
    int? catTimeout,
  }) => RadioModel(
    id:         id,
    mfg:        mfg,
    name:       name,
    baudRate:   baudRate   ?? this.baudRate,
    stopBits:   stopBits   ?? this.stopBits,
    writeDelay: writeDelay ?? this.writeDelay,
    catTimeout: catTimeout ?? this.catTimeout,
  );

  Map<String, dynamic> toJson() => {
    'id':         id,
    'mfg':        mfg,
    'name':       name,
    'baudRate':   baudRate,
    'stopBits':   stopBits,
    'writeDelay': writeDelay,
    'catTimeout': catTimeout,
  };

  factory RadioModel.fromJson(Map<String, dynamic> j) => RadioModel(
    id:         j['id']         as String,
    mfg:        j['mfg']        as String,
    name:       j['name']       as String,
    baudRate:   j['baudRate']   as int? ?? 38400,
    stopBits:   j['stopBits']   as int? ?? 1,
    writeDelay: j['writeDelay'] as int? ?? 0,
    catTimeout: j['catTimeout'] as int? ?? 5,
  );
}

// ── Known overrides for radios that need non-default CAT settings ─────────────
// Key is hamlib model ID. Most radios work fine at 38400/1/0 defaults.
const Map<String, Map<String, int>> _catOverrides = {
  '105': {'baudRate': 4800,  'stopBits': 2, 'writeDelay': 50, 'catTimeout': 5},  // FT-747GX
  '75':  {'baudRate': 4800,  'stopBits': 2, 'writeDelay': 50, 'catTimeout': 5},  // FT-757GX
  '76':  {'baudRate': 4800,  'stopBits': 2, 'writeDelay': 50, 'catTimeout': 5},  // FT-757GXII
  '104': {'baudRate': 4800,  'stopBits': 2, 'writeDelay': 50, 'catTimeout': 5},  // FT-736R
  '106': {'baudRate': 4800,  'stopBits': 2, 'writeDelay': 50, 'catTimeout': 5},  // FT-767GX
};

RadioModel _applyOverrides(RadioModel r) {
  final o = _catOverrides[r.id];
  if (o == null) return r;
  return r.copyWith(
    baudRate:   o['baudRate'],
    stopBits:   o['stopBits'],
    writeDelay: o['writeDelay'],
    catTimeout: o['catTimeout'],
  );
}

// ── States ────────────────────────────────────────────────────────────────────

enum ConnectionState { disconnected, connecting, connected }
enum RecordingState  { idle, recording }
enum RadioListState  { idle, loading, loaded, error }

// ── BridgeService ─────────────────────────────────────────────────────────────

class BridgeService extends ChangeNotifier {
  final FlutterBlueClassic _ble = FlutterBlueClassic();
  BluetoothConnection? _connection;
  StreamSubscription?  _inputSub;

  ConnectionState connectionState = ConnectionState.disconnected;
  RecordingState  recordingState  = RecordingState.idle;
  RadioListState  radioListState  = RadioListState.idle;

  String?      connectedDeviceName;
  String?      currentFilename;
  double?      currentFreqMhz;
  String?      lastSavedPath;
  String?      statusMessage;
  String?      errorMessage;
  String?      saveFolder;
  List<String> recordings = [];

  // ── Radio list ─────────────────────────────────────────────────────────────
  List<RadioModel> radioList     = [];
  RadioModel?      selectedRadio;
  String?          radioListError;

  // Pending JSON line buffer
  final List<int> _lineBuffer  = [];
  final List<int> _audioBuffer = [];
  bool _expectingAudio = false;
  bool _streamingAudio = false;

  // WAV state
  IOSink? _wavSink;
  File?   _wavFile;
  int     _audioByteCount = 0;
  int     _sampleRate     = 48000;
  int     _channels       = 1;
  int     _sampleWidth    = 2;

  // ── Completer for waiting on radio list response ───────────────────────────
  Completer<List<RadioModel>>? _radioListCompleter;

  // ── Init ───────────────────────────────────────────────────────────────────

  Future<void> loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    saveFolder = prefs.getString('save_folder');

    final savedRadioJson = prefs.getString('selected_radio');
    if (savedRadioJson != null) {
      try {
        selectedRadio = RadioModel.fromJson(
          jsonDecode(savedRadioJson) as Map<String, dynamic>
        );
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> saveRadio(RadioModel radio) async {
    selectedRadio = radio;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_radio', jsonEncode(radio.toJson()));
    notifyListeners();
    if (connectionState == ConnectionState.connected) {
      _sendRadioConfig(radio);
    }
  }

  // ── Bluetooth ──────────────────────────────────────────────────────────────

  Future<List<BluetoothDevice>> getPairedDevices() async {
    return await _ble.bondedDevices ?? [];
  }

  Future<void> connect(BluetoothDevice device) async {
    try {
      connectionState = ConnectionState.connecting;
      statusMessage   = 'Connecting to ${device.name}…';
      errorMessage    = null;
      notifyListeners();

      _connection         = await _ble.connect(device);
      connectedDeviceName = device.name;
      connectionState     = ConnectionState.connected;
      statusMessage       = 'Connected to ${device.name}';
      notifyListeners();

      _inputSub = _connection!.input!.listen(
        _onData,
        onDone:  _onDisconnected,
        onError: (_) => _onDisconnected(),
      );

      // Send radio config if one is already selected
      if (selectedRadio != null) {
        _sendRadioConfig(selectedRadio!);
      }

    } catch (e) {
      connectionState = ConnectionState.disconnected;
      errorMessage    = 'Connection failed: $e';
      statusMessage   = null;
      notifyListeners();
    }
  }

  void disconnect() {
    _radioListCompleter?.completeError('Disconnected');
    _radioListCompleter = null;
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

  // ── Radio list fetch ───────────────────────────────────────────────────────

  Future<void> fetchRadioList() async {
    if (connectionState != ConnectionState.connected) {
      radioListError = 'Not connected to HamBridge';
      radioListState = RadioListState.error;
      notifyListeners();
      return;
    }

    radioListState = RadioListState.loading;
    radioListError = null;
    notifyListeners();

    _radioListCompleter = Completer<List<RadioModel>>();
    _send({'action': 'get_radio_list'});

    try {
      final radios = await _radioListCompleter!.future
          .timeout(const Duration(seconds: 15));
      radioList      = radios;
      radioListState = RadioListState.loaded;
      radioListError = null;
    } catch (e) {
      radioListState = RadioListState.error;
      radioListError = 'Failed to load radio list: $e';
    }
    _radioListCompleter = null;
    notifyListeners();
  }

  // ── Recording ──────────────────────────────────────────────────────────────

  Future<void> toggleRecording(String grid, DateTime utcNow) async {
    if (recordingState == RecordingState.idle) {
      await _startRecording(grid, utcNow);
    } else {
      await _stopRecording();
    }
  }

  // ── Internal send ──────────────────────────────────────────────────────────

  void _sendRadioConfig(RadioModel radio) {
    _send({
      'action':       'set_radio',
      'hamlib_model': radio.id,
      'baud_rate':    radio.baudRate,
      'stop_bits':    radio.stopBits,
      'write_delay':  radio.writeDelay,
      'cat_timeout':  radio.catTimeout,
      'radio_name':   radio.name,
    });
  }

  void _send(Map<String, dynamic> cmd) {
    if (_connection == null) return;
    _connection!.output.add(
      Uint8List.fromList(utf8.encode('${jsonEncode(cmd)}\n'))
    );
  }

  // ── Incoming data ──────────────────────────────────────────────────────────

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

      // ── Radio list response ──────────────────────────────────────────────
      if (status == 'ok' && msg.containsKey('radios')) {
        final raw = msg['radios'] as List<dynamic>;
        final radios = raw.map((r) {
          final m = r as Map<String, dynamic>;
          final base = RadioModel(
            id:  m['id']  as String,
            mfg: m['mfg'] as String,
            name: m['name'] as String,
          );
          return _applyOverrides(base);
        }).toList();

        // Sort by manufacturer then name
        radios.sort((a, b) {
          final mfgCmp = a.mfg.compareTo(b.mfg);
          return mfgCmp != 0 ? mfgCmp : a.name.compareTo(b.name);
        });

        _radioListCompleter?.complete(radios);
        return;
      }

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
        statusMessage = 'Radio: ${msg['radio_name']}';
        notifyListeners();

      } else if (status == 'error') {
        final errMsg = msg['message'] as String?;
        // If we're waiting for a radio list, fail the completer
        if (_radioListCompleter != null && !_radioListCompleter!.isCompleted) {
          _radioListCompleter!.completeError(errMsg ?? 'Unknown error');
        } else {
          errorMessage = errMsg;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('JSON parse: $e  line=$line');
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

  // ── WAV ────────────────────────────────────────────────────────────────────

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
    if (_connection == null)  { errorMessage = 'Not connected';    notifyListeners(); return; }
    if (saveFolder == null)   { errorMessage = 'No save folder';   notifyListeners(); return; }
    if (selectedRadio == null){ errorMessage = 'No radio selected'; notifyListeners(); return; }
    errorMessage  = null;
    statusMessage = 'Querying frequency…';
    notifyListeners();
    _send({
      'action':   'start_recording',
      'grid':     grid.toUpperCase(),
      'utc_time': utcNow.toUtc().toIso8601String(),
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

  // ── Helpers ────────────────────────────────────────────────────────────────

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
