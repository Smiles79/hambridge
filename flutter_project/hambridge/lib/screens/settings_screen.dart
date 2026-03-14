import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/bridge_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _pickFolder(BuildContext context, BridgeService service) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose folder for recordings',
    );
    if (result != null) {
      service.saveFolder = result;
      service.notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('save_folder', result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<BridgeService>();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Colors.white54, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _sectionLabel('STORAGE'),
          const SizedBox(height: 10),
          _settingsTile(
            icon: Icons.folder_rounded,
            title: 'Save Folder',
            subtitle: service.saveFolder ?? 'Not set — tap to choose',
            onTap: () => _pickFolder(context, service),
            trailing: const Icon(Icons.chevron_right_rounded,
                color: Color(0xFF3A4258)),
          ),
          const SizedBox(height: 32),
          _sectionLabel('AUDIO'),
          const SizedBox(height: 10),
          _infoTile(
            icon: Icons.settings_input_component_rounded,
            title: 'Sample Rate',
            value: '48,000 Hz',
          ),
          const SizedBox(height: 8),
          _infoTile(
            icon: Icons.graphic_eq_rounded,
            title: 'Bit Depth',
            value: '16-bit PCM',
          ),
          const SizedBox(height: 8),
          _infoTile(
            icon: Icons.speaker_rounded,
            title: 'Channels',
            value: 'Mono',
          ),
          const SizedBox(height: 32),
          _sectionLabel('FILE NAMING'),
          const SizedBox(height: 10),
          _infoTile(
            icon: Icons.drive_file_rename_outline_rounded,
            title: 'Format',
            value: '{freq}_{date}_{time}_{grid}.wav',
          ),
          const SizedBox(height: 8),
          _infoTile(
            icon: Icons.schedule_rounded,
            title: 'Time Zone',
            value: 'UTC (from radio CAT)',
          ),
          const SizedBox(height: 32),
          _sectionLabel('ABOUT'),
          const SizedBox(height: 10),
          _infoTile(
            icon: Icons.radio_rounded,
            title: 'Radio',
            value: 'Yaesu FT-891',
          ),
          const SizedBox(height: 8),
          _infoTile(
            icon: Icons.device_hub_rounded,
            title: 'Interface',
            value: 'Digirig DR-891',
          ),
          const SizedBox(height: 8),
          _infoTile(
            icon: Icons.developer_board_rounded,
            title: 'Bridge',
            value: 'Raspberry Pi (hamlib rigctld)',
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 3,
        color: Color(0xFF5A6480),
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return GestureDetector(
      onTap: onTap,
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
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF00E5A0).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: const Color(0xFF00E5A0), size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Color(0xFF5A6480),
                          fontSize: 12,
                          fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2535),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF252D40)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF3A4258)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(title,
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ),
          Text(value,
              style: const TextStyle(
                  color: Color(0xFF00E5A0),
                  fontSize: 13,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
