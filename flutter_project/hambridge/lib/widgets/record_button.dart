import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RecordButton extends StatelessWidget {
  final bool recording;
  final bool enabled;
  final VoidCallback onTap;

  const RecordButton({
    super.key,
    required this.recording,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.mediumImpact();
              onTap();
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        width: double.infinity,
        height: 72,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: !enabled
              ? const Color(0xFF1A1F2E)
              : recording
                  ? const Color(0xFF1A3030)
                  : const Color(0xFF00E5A0).withOpacity(0.12),
          border: Border.all(
            color: !enabled
                ? const Color(0xFF252D40)
                : recording
                    ? const Color(0xFF00E5A0).withOpacity(0.5)
                    : const Color(0xFF00E5A0).withOpacity(0.6),
            width: recording ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                recording
                    ? Icons.stop_rounded
                    : Icons.fiber_manual_record_rounded,
                key: ValueKey(recording),
                size: 28,
                color: !enabled
                    ? const Color(0xFF3A4258)
                    : const Color(0xFF00E5A0),
              ),
            ),
            const SizedBox(width: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                recording ? 'STOP RECORDING' : 'START RECORDING',
                key: ValueKey(recording),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: !enabled
                      ? const Color(0xFF3A4258)
                      : const Color(0xFF00E5A0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
