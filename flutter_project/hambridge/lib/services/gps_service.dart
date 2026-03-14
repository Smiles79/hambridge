import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class GpsService extends ChangeNotifier {
  String _grid = 'UNKNOWN';
  double? _latitude;
  double? _longitude;
  String? _error;
  Timer? _timer;
  bool _initialised = false;

  String get grid => _grid;
  double? get latitude => _latitude;
  double? get longitude => _longitude;
  String? get error => _error;
  bool get hasGrid => _grid != 'UNKNOWN';

  // ── Start polling every 30 seconds ────────────────────────────────────────

  Future<void> start() async {
    if (_initialised) return;
    _initialised = true;

    await _requestPermission();
    await _update();

    // Update every 30 seconds
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _update());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _initialised = false;
  }

  // ── Permission ────────────────────────────────────────────────────────────

  Future<void> _requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      _error = 'Location permission permanently denied — enable in Settings';
      notifyListeners();
    }
  }

  // ── Get position and compute grid ─────────────────────────────────────────

  Future<void> _update() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );

      _latitude  = position.latitude;
      _longitude = position.longitude;
      _grid      = _toMaidenhead(position.latitude, position.longitude);
      _error     = null;
      notifyListeners();
    } catch (e) {
      _error = 'GPS unavailable: $e';
      notifyListeners();
    }
  }

  // ── Maidenhead grid locator calculation ───────────────────────────────────
  //
  // The Maidenhead Locator System divides the world into a grid.
  // A 6-character locator (e.g. EM72ab) is standard for amateur radio.
  //
  // Calculation:
  //   Longitude: shift from -180..+180 to 0..360
  //   Latitude:  shift from  -90..+90  to 0..180
  //
  //   Field (letter):  lon/20,  lat/10   → A-R
  //   Square (digit):  remainder/2, rem/1 → 0-9
  //   Subsquare (letter): remainder*12, rem*24 → a-x

  String _toMaidenhead(double lat, double lon) {
    // Shift to positive range
    double adjLon = lon + 180.0;
    double adjLat = lat + 90.0;

    // Field (2 letters)
    final fieldLon = String.fromCharCode(65 + (adjLon / 20).floor());
    final fieldLat = String.fromCharCode(65 + (adjLat / 10).floor());

    // Square (2 digits)
    final squareLon = ((adjLon % 20) / 2).floor();
    final squareLat = (adjLat % 10).floor();

    // Subsquare (2 lowercase letters)
    final subLon = ((adjLon % 2) * 12).floor();
    final subLat = ((adjLat % 1) * 24).floor();

    final subLetterLon = String.fromCharCode(97 + subLon);
    final subLetterLat = String.fromCharCode(97 + subLat);

    return '$fieldLon$fieldLat$squareLon$squareLat$subLetterLon$subLetterLat';
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
