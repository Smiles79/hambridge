import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/bridge_service.dart'
    hide ConnectionState; // use our local alias
import '../../services/bridge_service.dart' as svc;
import '../../widgets/frequency_display.dart';
import '../../widgets/record_button.dart';
import '../../widgets/status_bar.dart';
import '../../widgets/device_sheet.dart';
import '../../widgets/recordings_sheet.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _gridController = TextEditingController();
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
    _gridController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final service = context.watch<BridgeService>();
    final connected =
        service.connectionState == svc.ConnectionState.connected;
    final recording = service.recordingState == RecordingState.recording;

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
                    const SizedBox(height: 32),
                    _buildGridInput(connected, recording),
                    const SizedBox(height: 40),
                    RecordButton(
                      recording: recording,
                      enabled: connected && service.saveFolder != null,
                      onTap: () => service.toggleRecording(
                        _gridController.text.trim().isEmpty
                            ? 'UNKNOWN'
                            : _gridController.text.trim(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!connected)
                      _buildHint('Connect to your FT-891 Bridge to begin'),
                    if (connected && service.saveFolder == null)
                      _buildHint(
                          'Choose a save folder in Settings before recording'),
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
          // Logo / title
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FT-891',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 22,
                      color: const Color(0xFF00E5A0),
                    ),
              ),
              Text(
                'RECORDER',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      letterSpacing: 4,
                      fontSize: 10,
                    ),
              ),
            ],
          ),
          const Spacer(),
          // Recordings button
          IconButton(
            icon: const Icon(Icons.folder_open_rounded, size: 22),
            color: Colors.white54,
            onPressed: () => _showRecordingsSheet(context),
            tooltip: 'Recordings',
          ),
          // Settings button
          IconButton(
            icon: const Icon(Icons.tune_rounded, size: 22),
            color: Colors.white54,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            tooltip: 'Settings',
          ),
          // Bluetooth connect button
          GestureDetector(
            onTap: () => connected
                ? service.disconnect()
                : _showDeviceSheet(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                  Icon(
                    Icons.bluetooth_rounded,
                    size: 16,
                    color: connected
                        ? const Color(0xFF00E5A0)
                        : Colors.white38,
                  ),
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

  Widget _buildGridInput(bool connected, bool recording) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'GRID SQUARE',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 3,
            color: Color(0xFF5A6480),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _gridController,
          enabled: !recording,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 20,
            color: Colors.white,
            letterSpacing: 4,
          ),
          decoration: InputDecoration(
            hintText: 'EM72',
            hintStyle: const TextStyle(
              fontFamily: 'monospace',
              color: Color(0xFF3A4258),
              letterSpacing: 4,
            ),
            counterText: '',
            filled: true,
            fillColor: const Color(0xFF1E2535),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF252D40)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF252D40)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: Color(0xFF00E5A0), width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          ),
        ),
      ],
    );
  }

  Widget _buildHint(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF252D40)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: Color(0xFF5A6480)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF5A6480)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentRecording(BuildContext context, BridgeService service) {
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
                  Text(
                    latest,
                    style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                        fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
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
