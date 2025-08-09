import 'package:flutter/material.dart';

import 'notification_service.dart';
import 'storage.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/setup_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize local notifications plugin
  await NotificationService.instance.init();
  final marimo = await AppStorage.instance.loadMarimo();
  runApp(MarimoApp(startOnSetup: marimo == null));
}

class MarimoApp extends StatelessWidget {
  final bool startOnSetup;
  const MarimoApp({super.key, required this.startOnSetup});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'まりもっち',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.black),
          foregroundColor: Colors.black,
          backgroundColor: Colors.white,
        ),
      ),
      routes: {
        '/setup': (_) => const SetupPage(),
        '/home': (_) => const HomePage(),
        '/settings': (_) => const SettingsPage(),
      },
      home: startOnSetup ? const SetupPage() : const HomePage(),
    );
  }
}
