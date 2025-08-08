import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_service.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'pages/setup_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize local notifications plugin
  await NotificationService.instance.init();
  runApp(const MarimoApp());
}

class MarimoApp extends StatelessWidget {
  const MarimoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'まりもっち',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
      ),
      routes: {
        '/setup': (_) => const SetupPage(),
        '/home': (_) => const HomePage(),
        '/settings': (_) => const SettingsPage(),
      },
      home: const HomePage(),
    );
  }
}
