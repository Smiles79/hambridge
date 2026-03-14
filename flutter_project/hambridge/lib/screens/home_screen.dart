import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/bridge_service.dart'
    hide ConnectionState;
import '../services/bridge_service.dart' as svc;
import '../services/gps_service.dart';
import '../widgets/frequency_display.dart';
import '../widgets/record_button.dart';
import '../widgets/status_bar.dart';
import '../widgets/device_sheet.dart';
import '../widgets/recordings_sheet.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _showDeviceSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const DeviceSheet(),
    );
  }

  void _showRecordingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const RecordingsSheet(),
    );
  }

  Future<void> _onRecordTap(
      BuildContext context, BridgeService service, GpsService gps) async {
    HapticFeedback.mediumImpact();

    // UTC time always from phone
    final utcNow = DateTime.now().toUtc();
    await service.toggleRecording(gps.grid, utcNow);
  }

  @override
  Widget build(BuildContext context) {
    final service   = context.watch<BridgeService>();
    final gps       = context.watch<GpsService>();
    final connected = service.connectionState == svc.ConnectionState.connected;
    final recording = service.recordingState == RecordingState.recording;

    final canRecord = connected &&
        service.saveFolder != null &&
        gps.hasGrid;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context, service, connected),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    FrequencyDisplay(
                      freqMhz: service.currentFreqMhz,
                      recording: recording,
                      pulseController: _pulseController,
                    ),
                    const SizedBox(height: 20),
                    _buildInfoRow(gps, service),
                    const SizedBox(height: 32),
                    RecordButton(
                      recording: recording,
                      enabled: canRecord,
                      onTap: () => _onRecordTap(context, service, gps),
                    ),
                    const SizedBox(height: 16),
                    _buildHints(connected, service, gps),
                    const SizedBox(height: 32),
                    StatusBar(service: service),
                    const SizedBox(height: 32),
                    if (service.recordings.isNotEmpty)
                      _buildRecentRecording(context, service),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(
      BuildContext context, BridgeService service, bool connected) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HAM',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 22,
                      color: const Color(0xFF00E5A0),
                    ),
              ),
              Text(
                'BRIDGE',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      letterSpacing: 4,
                      fontSize: 10,
                    ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.folder_open_rounded, size: 22),
            color: Colors.white54,
            onPressed: () => _showRecordingsSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, size: 22),
            color: Colors.white54,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          GestureDetector(
            onTap: () => connected
                ? service.disconnect()
                : _showDeviceSheet(context),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: connected
                    ? const Color(0xFF00E5A0).withOpacity(0.12)
                    : const Color(0xFF1E2535),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: connected
                      ? const Color(0xFF00E5A0).withOpacity(0.4)
                      : const Color(0xFF252D40),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bluetooth_rounded,
                      size: 16,
                      color: connected
                          ? const Color(0xFF00E5A0)
                          : Colors.white38),
                  const SizedBox(width: 6),
                  Text(
                    connected
                        ? (service.connectedDeviceName ?? 'Connected')
                        : 'Connect',
                    style: TextStyle(
                      fontSize: 13,
                      color: connected
                          ? const Color(0xFF00E5A0)
                          : Colors.white54,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows GPS grid, UTC clock, and radio model in a single row of tiles
  Widget _buildInfoRow(GpsService gps, BridgeService service) {
    final utc = DateTime.now().toUtc();
    final timeStr =
        '${utc.hour.toString().padLeft(2, '0')}:'
        '${utc.minute.toString().padLeft(2, '0')} UTC';

    return Row(
      children: [
        Expanded(child: _infoTile(
          icon: Icons.location_on_rounded,
          label: 'GRID',
          value: gps.hasGrid ? gps.grid.toUpperCase() : '—',
          accent: gps.hasGrid,
          error: gps.error != null,
        )),
        const SizedBox(width: 10),
        Expanded(child: _infoTile(
          icon: Icons.schedule_rounded,
          label: 'UTC',
          value: timeStr,
          accent: false,
        )),
        const SizedBox(width: 10),
        Expanded(child: _infoTile(
          icon: Icons.radio_rounded,
          label: 'RADIO',
          value: service.selectedRadio.name
              .replaceAll('Yaesu ', ''),
          accent: false,
        )),
      ],
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
    required bool accent,
    bool error = false,
  }) {
    final color = error
        ? const Color(0xFFE05A6A)
        : accent
            ? const Color(0xFF00E5A0)
            : Colors.white70;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent
              ? const Color(0xFF00E5A0).withOpacity(0.3)
              : const Color(0xFF252D40),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: const Color(0xFF5A6480)),
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(
                      fontSize: 9,
                      letterSpacing: 2,
                      color: Color(0xFF5A6480),
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildHints(
      bool connected, BridgeService service, GpsService gps) {
    final hints = <String>[];
    if (!connected) hints.add('Connect to your HamBridge Pi to begin');
    if (connected && service.saveFolder == null)
      hints.add('Choose a save folder in Settings');
    if (!gps.hasGrid && gps.error != null)
      hints.add('GPS unavailable — check location permissions');
    if (!gps.hasGrid && gps.error == null)
      hints.add('Waiting for GPS fix…');

    if (hints.isEmpty) return const SizedBox.shrink();

    return Column(
      children: hints
          .map((h) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1F2E),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: const Color(0xFF252D40)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 16, color: Color(0xFF5A6480)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(h,
                            style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF5A6480))),
                      ),
                    ],
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildRecentRecording(
      BuildContext context, BridgeService service) {
    final latest = service.recordings.first;
    return GestureDetector(
      onTap: () => _showRecordingsSheet(context),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2535),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF252D40)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF00E5A0).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.audio_file_rounded,
                  color: Color(0xFF00E5A0), size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('LAST RECORDING',
                      style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 2,
                          color: Color(0xFF5A6480))),
                  const SizedBox(height: 4),
                  Text(latest,
                      style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white70,
                          fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFF3A4258)),
          ],
        ),
      ),
    );
  }
}
