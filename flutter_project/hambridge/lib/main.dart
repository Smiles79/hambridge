import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'services/bridge_service.dart';
import 'services/gps_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Initialise foreground task service (lock screen persistence)
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'hambridge_recording',
      channelName: 'HamBridge Recording',
      channelDescription: 'Keeps HamBridge active during recording',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  final bridgeService = BridgeService();
  await bridgeService.loadPrefs();

  final gpsService = GpsService();
  await gpsService.start();

  // Start foreground task immediately — keeps app visible on lock screen
  // whenever the app is open, not just during recording (like Google Maps)
  await FlutterForegroundTask.startService(
    notificationTitle: 'HamBridge',
    notificationText: 'Tap to return to HamBridge',
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: bridgeService),
        ChangeNotifierProvider.value(value: gpsService),
      ],
      child: const HamBridgeApp(),
    ),
  );
}

class HamBridgeApp extends StatelessWidget {
  const HamBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        title: 'HamBridge',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: const HomeScreen(),
      ),
    );
  }

  ThemeData _buildTheme() {
    const bg      = Color(0xFF0D0F14);
    const surface = Color(0xFF161B24);
    const card    = Color(0xFF1E2535);
    const accent  = Color(0xFF00E5A0);
    const dimText = Color(0xFF5A6480);

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
