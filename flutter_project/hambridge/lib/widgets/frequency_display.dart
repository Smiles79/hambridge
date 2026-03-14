import 'package:flutter/material.dart';

class FrequencyDisplay extends StatelessWidget {
  final double? freqMhz;
  final bool recording;
  final AnimationController pulseController;

  const FrequencyDisplay({
    super.key,
    required this.freqMhz,
    required this.recording,
    required this.pulseController,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseController,
      builder: (context, child) {
        final glowOpacity = recording
            ? 0.15 + (pulseController.value * 0.15)
            : 0.0;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
          decoration: BoxDecoration(
            color: const Color(0xFF161B24),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: recording
                  ? const Color(0xFF00E5A0)
                      .withOpacity(0.3 + pulseController.value * 0.2)
                  : const Color(0xFF252D40),
              width: recording ? 1.5 : 1,
            ),
            boxShadow: recording
                ? [
                    BoxShadow(
                      color: const Color(0xFF00E5A0).withOpacity(glowOpacity),
                      blurRadius: 40,
                      spreadRadius: 10,
                    )
                  ]
                : [],
          ),
          child: Column(
            children: [
              Text(
                'FREQUENCY',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 4,
                  color: recording
                      ? const Color(0xFF00E5A0).withOpacity(0.7)
                      : const Color(0xFF3A4258),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                freqMhz != null
                    ? '${freqMhz!.toStringAsFixed(4)} MHz'
                    : '– – – – – –',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: freqMhz != null
                      ? const Color(0xFF00E5A0)
                      : const Color(0xFF2A3348),
                  letterSpacing: 2,
                  shadows: recording && freqMhz != null
                      ? [
                          Shadow(
                            color: const Color(0xFF00E5A0)
                                .withOpacity(0.5 + pulseController.value * 0.3),
                            blurRadius: 20,
                          )
                        ]
                      : [],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (recording) ...[
                    _RecordingIndicator(controller: pulseController),
                    const SizedBox(width: 8),
                    const Text(
                      'RECORDING',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 3,
                        color: Color(0xFF00E5A0),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ] else
                    const Text(
                      'STANDBY',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 3,
                        color: Color(0xFF3A4258),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RecordingIndicator extends StatelessWidget {
  final AnimationController controller;
  const _RecordingIndicator({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.lerp(
            const Color(0xFF00E5A0),
            const Color(0xFF00E5A0).withOpacity(0.3),
            controller.value,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E5A0)
                  .withOpacity(0.4 + controller.value * 0.4),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}
