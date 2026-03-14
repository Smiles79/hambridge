import 'package:flutter/material.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/bridge_service.dart';

class DeviceSheet extends StatefulWidget {
  const DeviceSheet({super.key});

  @override
  State<DeviceSheet> createState() => _DeviceSheetState();
}

class _DeviceSheetState extends State<DeviceSheet> {
  List<BluetoothDevice> _devices = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    // Request BT permissions
    final status = await Permission.bluetoothConnect.request();
    if (!status.isGranted) {
      setState(() {
        _error = 'Bluetooth permission denied';
        _loading = false;
      });
      return;
    }

    try {
      final service = context.read<BridgeService>();
      final devices = await service.getPairedDevices();
      setState(() {
        _devices = devices;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load paired devices: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.85,
      minChildSize: 0.3,
      builder: (_, controller) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF3A4258),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const Text(
                  'PAIRED DEVICES',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 3,
                    color: Color(0xFF5A6480),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (!_loading)
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _loading = true);
                      _loadDevices();
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Refresh'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF5A6480),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF00E5A0),
                        strokeWidth: 2,
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: Color(0xFFE05A6A), fontSize: 13)))
                      : _devices.isEmpty
                          ? const Center(
                              child: Text(
                                'No paired devices found.\nPair the Pi in Android Bluetooth settings first.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Color(0xFF5A6480), fontSize: 14),
                              ),
                            )
                          : ListView.separated(
                              controller: controller,
                              itemCount: _devices.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) =>
                                  _DeviceTile(device: _devices[i]),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final BluetoothDevice device;
  const _DeviceTile({required this.device});

  @override
  Widget build(BuildContext context) {
    final service = context.read<BridgeService>();
    final isBridge = (device.name ?? '').toLowerCase().contains('ft891') ||
        (device.name ?? '').toLowerCase().contains('bridge');

    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        service.connect(device);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2535),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isBridge
                ? const Color(0xFF00E5A0).withOpacity(0.3)
                : const Color(0xFF252D40),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isBridge
                    ? const Color(0xFF00E5A0).withOpacity(0.1)
                    : const Color(0xFF252D40),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.bluetooth_rounded,
                color: isBridge
                    ? const Color(0xFF00E5A0)
                    : const Color(0xFF5A6480),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name ?? 'Unknown Device',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    device.address,
                    style: const TextStyle(
                        color: Color(0xFF5A6480),
                        fontSize: 12,
                        fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            if (isBridge)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5A0).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: const Color(0xFF00E5A0).withOpacity(0.3)),
                ),
                child: const Text(
                  'Bridge',
                  style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF00E5A0),
                      fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
