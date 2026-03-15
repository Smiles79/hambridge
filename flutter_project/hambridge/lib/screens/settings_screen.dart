import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/bridge_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Advanced CAT settings controllers
  final _baudController     = TextEditingController();
  final _stopBitsController = TextEditingController();
  final _delayController    = TextEditingController();
  final _timeoutController  = TextEditingController();
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _syncControllersFromSelected();
  }

  void _syncControllersFromSelected() {
    final service = context.read<BridgeService>();
    final r = service.selectedRadio;
    if (r != null) {
      _baudController.text     = r.baudRate.toString();
      _stopBitsController.text = r.stopBits.toString();
      _delayController.text    = r.writeDelay.toString();
      _timeoutController.text  = r.catTimeout.toString();
    }
  }

  @override
  void dispose() {
    _baudController.dispose();
    _stopBitsController.dispose();
    _delayController.dispose();
    _timeoutController.dispose();
    super.dispose();
  }

  Future<void> _pickFolder(BridgeService service) async {
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

  void _saveAdvancedSettings(BridgeService service) {
    final r = service.selectedRadio;
    if (r == null) return;

    final updated = r.copyWith(
      baudRate:   int.tryParse(_baudController.text)     ?? r.baudRate,
      stopBits:   int.tryParse(_stopBitsController.text) ?? r.stopBits,
      writeDelay: int.tryParse(_delayController.text)    ?? r.writeDelay,
      catTimeout: int.tryParse(_timeoutController.text)  ?? r.catTimeout,
    );
    service.saveRadio(updated);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('CAT settings saved'),
        backgroundColor: Color(0xFF1E2535),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showRadioPicker(BuildContext context, BridgeService service) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _RadioPickerSheet(
        service: service,
        onSelected: (radio) {
          service.saveRadio(radio);
          _baudController.text     = radio.baudRate.toString();
          _stopBitsController.text = radio.stopBits.toString();
          _delayController.text    = radio.writeDelay.toString();
          _timeoutController.text  = radio.catTimeout.toString();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<BridgeService>();
    final connected = service.connectionState == ConnectionState.connected;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        elevation: 0,
        title: const Text('Settings',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white54, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Radio selection ──────────────────────────────────────────────
          _sectionLabel('RADIO'),
          const SizedBox(height: 10),
          _radioSelector(context, service, connected),
          const SizedBox(height: 8),
          if (!connected)
            _hintTile('Connect to HamBridge to load all supported radios'),
          if (connected && service.radioListState == RadioListState.error)
            _hintTile(service.radioListError ?? 'Error loading radio list', isError: true),

          const SizedBox(height: 16),

          // ── Advanced CAT settings ────────────────────────────────────────
          GestureDetector(
            onTap: () => setState(() => _showAdvanced = !_showAdvanced),
            child: Row(
              children: [
                const Text('ADVANCED CAT SETTINGS',
                    style: TextStyle(
                        fontSize: 11, letterSpacing: 3,
                        color: Color(0xFF5A6480), fontWeight: FontWeight.w600)),
                const Spacer(),
                Icon(
                  _showAdvanced ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: const Color(0xFF5A6480), size: 18,
                ),
              ],
            ),
          ),

          if (_showAdvanced) ...[
            const SizedBox(height: 10),
            _catField('Baud Rate', _baudController, hint: '38400'),
            const SizedBox(height: 8),
            _catField('Stop Bits', _stopBitsController, hint: '1'),
            const SizedBox(height: 8),
            _catField('Write Delay (ms)', _delayController, hint: '0'),
            const SizedBox(height: 8),
            _catField('CAT Timeout (s)', _timeoutController, hint: '5'),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _saveAdvancedSettings(service),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5A0).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF00E5A0).withOpacity(0.4)),
                ),
                child: const Center(
                  child: Text('Save CAT Settings',
                      style: TextStyle(
                          color: Color(0xFF00E5A0),
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                ),
              ),
            ),
          ],

          const SizedBox(height: 32),

          // ── Storage ──────────────────────────────────────────────────────
          _sectionLabel('STORAGE'),
          const SizedBox(height: 10),
          _settingsTile(
            icon: Icons.folder_rounded,
            title: 'Save Folder',
            subtitle: service.saveFolder ?? 'Not set — tap to choose',
            onTap: () => _pickFolder(service),
            trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFF3A4258)),
          ),

          const SizedBox(height: 32),

          // ── Audio ────────────────────────────────────────────────────────
          _sectionLabel('AUDIO'),
          const SizedBox(height: 10),
          _infoTile(icon: Icons.settings_input_component_rounded, title: 'Sample Rate', value: '48,000 Hz'),
          const SizedBox(height: 8),
          _infoTile(icon: Icons.graphic_eq_rounded, title: 'Bit Depth', value: '16-bit PCM'),
          const SizedBox(height: 8),
          _infoTile(icon: Icons.speaker_rounded, title: 'Channels', value: 'Mono'),

          const SizedBox(height: 32),

          // ── File naming ──────────────────────────────────────────────────
          _sectionLabel('FILE NAMING'),
          const SizedBox(height: 10),
          _infoTile(icon: Icons.drive_file_rename_outline_rounded, title: 'Format', value: '{freq}_{date}_{time}_{grid}.wav'),
          const SizedBox(height: 8),
          _infoTile(icon: Icons.schedule_rounded, title: 'Time', value: 'UTC from phone'),
          const SizedBox(height: 8),
          _infoTile(icon: Icons.location_on_rounded, title: 'Grid', value: 'GPS Maidenhead (auto)'),

          const SizedBox(height: 32),

          // ── Hardware ─────────────────────────────────────────────────────
          _sectionLabel('HARDWARE'),
          const SizedBox(height: 10),
          _infoTile(icon: Icons.developer_board_rounded, title: 'Bridge', value: 'Raspberry Pi (HamBridge)'),
          const SizedBox(height: 8),
          _infoTile(icon: Icons.device_hub_rounded, title: 'Interface', value: 'DR-891 / Digirig Mobile'),
        ],
      ),
    );
  }

  Widget _radioSelector(BuildContext context, BridgeService service, bool connected) {
    final selected = service.selectedRadio;
    final loading  = service.radioListState == RadioListState.loading;

    return GestureDetector(
      onTap: connected
          ? () {
              if (service.radioListState != RadioListState.loaded) {
                service.fetchRadioList();
              }
              _showRadioPicker(context, service);
            }
          : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2535),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected != null
                ? const Color(0xFF00E5A0).withOpacity(0.4)
                : const Color(0xFF252D40),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF00E5A0).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.radio_rounded,
                  color: Color(0xFF00E5A0), size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selected?.name ?? 'Select radio',
                    style: TextStyle(
                      color: selected != null ? Colors.white : const Color(0xFF5A6480),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (selected != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Model ${selected.id} · ${selected.baudRate} baud',
                      style: const TextStyle(
                          color: Color(0xFF5A6480),
                          fontSize: 12,
                          fontFamily: 'monospace'),
                    ),
                  ],
                ],
              ),
            ),
            if (loading)
              const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                    color: Color(0xFF00E5A0), strokeWidth: 2),
              )
            else
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF3A4258)),
          ],
        ),
      ),
    );
  }

  Widget _catField(String label, TextEditingController controller, {String hint = ''}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2535),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF252D40)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(
                  color: Color(0xFF00E5A0),
                  fontFamily: 'monospace',
                  fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Color(0xFF3A4258)),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hintTile(String text, {bool isError = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F2E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isError
                ? const Color(0xFFE05A6A).withOpacity(0.4)
                : const Color(0xFF252D40)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
            size: 15,
            color: isError ? const Color(0xFFE05A6A) : const Color(0xFF5A6480),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12,
                    color: isError
                        ? const Color(0xFFE05A6A)
                        : const Color(0xFF5A6480))),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) => Text(label,
      style: const TextStyle(
          fontSize: 11, letterSpacing: 3,
          color: Color(0xFF5A6480), fontWeight: FontWeight.w600));

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
              width: 36, height: 36,
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
                          color: Color(0xFF5A6480), fontSize: 12,
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
          Expanded(child: Text(title,
              style: const TextStyle(color: Colors.white70, fontSize: 14))),
          Text(value,
              style: const TextStyle(
                  color: Color(0xFF00E5A0), fontSize: 12, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

// =============================================================================
//  Radio picker bottom sheet with search
// =============================================================================

class _RadioPickerSheet extends StatefulWidget {
  final BridgeService service;
  final void Function(RadioModel) onSelected;

  const _RadioPickerSheet({
    required this.service,
    required this.onSelected,
  });

  @override
  State<_RadioPickerSheet> createState() => _RadioPickerSheetState();
}

class _RadioPickerSheetState extends State<_RadioPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Trigger fetch if not already loaded
    if (widget.service.radioListState == RadioListState.idle ||
        widget.service.radioListState == RadioListState.error) {
      widget.service.fetchRadioList();
    }
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RadioModel> get _filtered {
    final list = widget.service.radioList;
    if (_query.isEmpty) return list;
    return list.where((r) =>
      r.name.toLowerCase().contains(_query) ||
      r.id.contains(_query) ||
      r.mfg.toLowerCase().contains(_query)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.service,
      builder: (context, _) {
        final state = widget.service.radioListState;

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (_, controller) => Column(
            children: [
              // Handle
              const SizedBox(height: 12),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A4258),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Text('SELECT RADIO',
                        style: TextStyle(
                            fontSize: 12, letterSpacing: 3,
                            color: Color(0xFF5A6480), fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (state == RadioListState.loaded)
                      Text('${widget.service.radioList.length} radios',
                          style: const TextStyle(
                              color: Color(0xFF5A6480), fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2535),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF252D40)),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Search by name, manufacturer, or model number…',
                      hintStyle: TextStyle(color: Color(0xFF3A4258), fontSize: 13),
                      prefixIcon: Icon(Icons.search_rounded,
                          color: Color(0xFF5A6480), size: 20),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // List
              Expanded(
                child: state == RadioListState.loading
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                                color: Color(0xFF00E5A0), strokeWidth: 2),
                            SizedBox(height: 16),
                            Text('Loading radio list from Pi…',
                                style: TextStyle(
                                    color: Color(0xFF5A6480), fontSize: 13)),
                          ],
                        ),
                      )
                    : state == RadioListState.error
                        ? Center(
                            child: Text(
                              widget.service.radioListError ?? 'Error',
                              style: const TextStyle(
                                  color: Color(0xFFE05A6A), fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : _filtered.isEmpty
                            ? const Center(
                                child: Text('No radios found',
                                    style: TextStyle(
                                        color: Color(0xFF5A6480), fontSize: 14)),
                              )
                            : ListView.separated(
                                controller: controller,
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                itemCount: _filtered.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 6),
                                itemBuilder: (_, i) {
                                  final radio  = _filtered[i];
                                  final selected =
                                      widget.service.selectedRadio?.id == radio.id;
                                  return GestureDetector(
                                    onTap: () {
                                      widget.onSelected(radio);
                                      Navigator.pop(context);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? const Color(0xFF00E5A0).withOpacity(0.08)
                                            : const Color(0xFF1E2535),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: selected
                                              ? const Color(0xFF00E5A0).withOpacity(0.4)
                                              : const Color(0xFF252D40),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(radio.name,
                                                    style: TextStyle(
                                                      color: selected
                                                          ? Colors.white
                                                          : Colors.white70,
                                                      fontWeight: FontWeight.w500,
                                                      fontSize: 14,
                                                    )),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Model ${radio.id} · ${radio.baudRate} baud',
                                                  style: const TextStyle(
                                                      color: Color(0xFF5A6480),
                                                      fontSize: 11,
                                                      fontFamily: 'monospace'),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (selected)
                                            const Icon(Icons.check_circle_rounded,
                                                color: Color(0xFF00E5A0), size: 18),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}
