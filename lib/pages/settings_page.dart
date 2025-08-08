import 'package:flutter/material.dart';

import '../models.dart';
import '../notification_service.dart';
import '../storage.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  UserSetting? _settings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await AppStorage.instance.loadSettings();
    setState(() => _settings = s);
  }

  Future<void> _save() async {
    if (_settings == null) return;
    await AppStorage.instance.saveSettings(_settings!);
    final m = await AppStorage.instance.loadMarimo();
    if (m != null) {
      await NotificationService.instance.scheduleWaterChangeReminders(
        lastWaterChangeAt: m.lastWaterChangeAt,
        enabled: _settings!.notificationsEnabled,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    if (s == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('通知ON/OFF', style: TextStyle(fontSize: 17)),
            value: s.notificationsEnabled,
            onChanged: (v) async {
              setState(() => _settings = s..notificationsEnabled = v);
              await _save();
            },
          ),
          SwitchListTile(
            title: const Text('スクショに透かしロゴ', style: TextStyle(fontSize: 17)),
            value: s.screenshotWatermark,
            onChanged: (v) async {
              setState(() => _settings = s..screenshotWatermark = v);
              await _save();
            },
          ),
          SwitchListTile(
            title: const Text('ハプティクス', style: TextStyle(fontSize: 17)),
            subtitle: const Text('操作時の軽い振動フィードバックを有効にします', style: TextStyle(fontSize: 13)),
            value: s.haptics,
            onChanged: (v) async {
              setState(() => _settings = s..haptics = v);
              await _save();
            },
          ),
          SwitchListTile(
            title: const Text('光合成・浮遊アニメ', style: TextStyle(fontSize: 17)),
            value: s.floatingEnabled,
            onChanged: (v) async {
              setState(() => _settings = s..floatingEnabled = v);
              await _save();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
