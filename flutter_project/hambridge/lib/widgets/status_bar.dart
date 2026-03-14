import 'package:flutter/material.dart';
import '../../services/bridge_service.dart';

class StatusBar extends StatelessWidget {
  final BridgeService service;
  const StatusBar({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    final hasError = service.errorMessage != null;
    final message = hasError
        ? service.errorMessage!
        : service.statusMessage ?? 'Ready';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: hasError
            ? const Color(0xFF2A1A1E)
            : const Color(0xFF161B24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasError
              ? const Color(0xFFE05A6A).withOpacity(0.4)
              : const Color(0xFF252D40),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasError
                ? Icons.warning_amber_rounded
                : Icons.terminal_rounded,
            size: 15,
            color: hasError
                ? const Color(0xFFE05A6A)
                : const Color(0xFF5A6480),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: hasError
                    ? const Color(0xFFE05A6A)
                    : const Color(0xFF8A96B0),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
