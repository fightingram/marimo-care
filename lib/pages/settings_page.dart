import 'package:flutter/material.dart';

import '../models.dart';
import '../notification_service.dart';
import '../storage.dart';
import '../backgrounds.dart';
import 'package:image_picker/image_picker.dart';

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
        enabled: _settings!.notificationsEnabled && m.state == MarimoState.alive,
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
            subtitle: const Text('日中は「光合成中」インジケーターと、マリモがゆっくり漂います'),
            value: s.floatingEnabled,
            onChanged: (v) async {
              setState(() => _settings = s..floatingEnabled = v);
              await _save();
            },
          ),
          SwitchListTile(
            title: const Text('背景画像に水槽効果をのせる', style: TextStyle(fontSize: 17)),
            subtitle: const Text('カスタム背景の上に水の色味・反射・わずかなブラーを重ねます', style: TextStyle(fontSize: 13)),
            value: s.useWaterEffectOnCustomBackground,
            onChanged: (v) async {
              setState(() => _settings = s..useWaterEffectOnCustomBackground = v);
              await _save();
            },
          ),
          const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.image),
            title: const Text('背景を変更', style: TextStyle(fontSize: 17)),
            subtitle: Text(
              (s.customBackgroundPath != null && s.customBackgroundPath!.isNotEmpty)
                  ? 'カスタム画像'
                  : 'プリセット: ' + presetBackgrounds[(s.backgroundIndex) % presetBackgrounds.length].name,
            ),
            onTap: () async {
              final res = await Navigator.of(context).push<_BgResultSettings>(
                MaterialPageRoute(builder: (_) => const BackgroundGalleryPage()),
              );
              if (res != null) {
                if (res.isCustom) {
                  final newS = s..customBackgroundPath = res.customPath!;
                  setState(() => _settings = newS);
                  await _save();
                } else {
                  final newS = s
                    ..backgroundIndex = res.index!
                    ..customBackgroundPath = null;
                  setState(() => _settings = newS);
                  await _save();
                }
              }
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _BgResultSettings {
  final int? index;
  final String? customPath;
  final bool isCustom;
  const _BgResultSettings.preset(this.index)
      : customPath = null,
        isCustom = false;
  const _BgResultSettings.custom(this.customPath)
      : index = null,
        isCustom = true;
}

class BackgroundGalleryPage extends StatelessWidget {
  const BackgroundGalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('背景ギャラリー')),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: presetBackgrounds.length + 1,
        itemBuilder: (context, i) {
          if (i == presetBackgrounds.length) {
            return GestureDetector(
              onTap: () async {
                final picker = ImagePicker();
                final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 4096, maxHeight: 4096);
                if (picked != null) {
                  if (context.mounted) Navigator.of(context).pop(_BgResultSettings.custom(picked.path));
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_library, color: Colors.white),
                      SizedBox(height: 6),
                      Text('アルバム', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            );
          }
          return GestureDetector(
            onTap: () => Navigator.of(context).pop(_BgResultSettings.preset(i)),
            child: Container(
              decoration: BoxDecoration(
                gradient: presetBackgrounds[i].gradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  presetBackgrounds[i].name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
