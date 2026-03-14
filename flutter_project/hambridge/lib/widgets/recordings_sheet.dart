import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/bridge_service.dart';

class RecordingsSheet extends StatelessWidget {
  const RecordingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<BridgeService>();
    final recordings = service.recordings;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
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
                  'RECORDINGS',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 3,
                    color: Color(0xFF5A6480),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${recordings.length} files',
                  style: const TextStyle(
                      color: Color(0xFF5A6480), fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: recordings.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.mic_off_rounded,
                              size: 48, color: Color(0xFF2A3348)),
                          SizedBox(height: 16),
                          Text(
                            'No recordings yet',
                            style: TextStyle(
                                color: Color(0xFF5A6480), fontSize: 15),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Connect and press Record to start',
                            style: TextStyle(
                                color: Color(0xFF3A4258), fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      controller: controller,
                      itemCount: recordings.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (_, i) =>
                          _RecordingTile(filename: recordings[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingTile extends StatelessWidget {
  final String filename;
  const _RecordingTile({required this.filename});

  /// Parse freq, date, time, grid from filename like:
  /// 14.2250MHz_20260313_183045_EM72.wav
  Map<String, String> _parse() {
    try {
      final name = filename.replaceAll('.wav', '');
      final parts = name.split('_');
      return {
        'freq': parts[0],
        'date': _formatDate(parts[1]),
        'time': _formatTime(parts[2]),
        'grid': parts.length > 3 ? parts[3] : '',
      };
    } catch (_) {
      return {'freq': filename, 'date': '', 'time': '', 'grid': ''};
    }
  }

  String _formatDate(String d) {
    if (d.length < 8) return d;
    return '${d.substring(0, 4)}-${d.substring(4, 6)}-${d.substring(6, 8)}';
  }

  String _formatTime(String t) {
    if (t.length < 6) return t;
    return '${t.substring(0, 2)}:${t.substring(2, 4)}:${t.substring(4, 6)} UTC';
  }

  @override
  Widget build(BuildContext context) {
    final info = _parse();

    return GestureDetector(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: filename));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Filename copied'),
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFF1E2535),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2535),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF252D40)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF00E5A0).withOpacity(0.08),
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
                  Text(
                    info['freq'] ?? '',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 16,
                      color: Color(0xFF00E5A0),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        info['date'] ?? '',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF5A6480)),
                      ),
                      const Text('  ·  ',
                          style:
                              TextStyle(color: Color(0xFF3A4258))),
                      Text(
                        info['time'] ?? '',
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF5A6480),
                            fontFamily: 'monospace'),
                      ),
                      if ((info['grid'] ?? '').isNotEmpty) ...[
                        const Text('  ·  ',
                            style: TextStyle(
                                color: Color(0xFF3A4258))),
                        Text(
                          info['grid']!,
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF5A6480),
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
