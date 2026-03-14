import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/bridge_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final prefs = await SharedPreferences.getInstance();
  final service = BridgeService();
  service.saveFolder = prefs.getString('save_folder');

  runApp(
    ChangeNotifierProvider.value(
      value: service,
      child: const HamBridge(),
    ),
  );
}

class HamBridge extends StatelessWidget {
  const HamBridge({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HamBridge',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const HomeScreen(),
    );
  }

  ThemeData _buildTheme() {
    const bg       = Color(0xFF0D0F14);
    const surface  = Color(0xFF161B24);
    const card     = Color(0xFF1E2535);
    const accent   = Color(0xFF00E5A0);   // sharp green — radio/scope feel
    const dimText  = Color(0xFF5A6480);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accent,
        surface: surface,
        onSurface: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF252D40), width: 1),
        ),
      ),
      textTheme: const TextTheme(
        // Display font: monospaced for frequency readouts
        displayLarge: TextStyle(
          fontFamily: 'monospace',
          color: accent,
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
        ),
        titleLarge: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        bodyMedium: TextStyle(color: Colors.white70),
        bodySmall: TextStyle(color: dimText, fontSize: 12),
      ),
    );
  }
}
