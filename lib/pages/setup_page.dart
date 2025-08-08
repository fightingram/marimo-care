import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../storage.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _nameController = TextEditingController();
  int _bgIndex = 0;

  Future<void> _start() async {
    final name = _nameController.text.trim().isEmpty ? 'まりも' : _nameController.text.trim();
    final now = DateTime.now();
    final m = Marimo(
      id: const Uuid().v4(),
      name: name,
      state: MarimoState.alive,
      sizeMm: 5.0,
      cleanliness: 100,
      startedAt: now,
      lastWaterChangeAt: now,
      lastGrowthTickAt: DateTime(now.year, now.month, now.day),
      lastInteractionAt: now,
      waterBoostUntil: null,
    );
    await AppStorage.instance.saveMarimo(m);
    // Save initial background index into settings
    final settings = await AppStorage.instance.loadSettings();
    settings.backgroundIndex = _bgIndex;
    await AppStorage.instance.saveSettings(settings);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('はじめに', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('まりもの名前を決めましょう', style: TextStyle(fontSize: 17)),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(hintText: '例: まりもっち'),
            ),
            const SizedBox(height: 24),
            const Text('背景を選んでください（後で変更できます）', style: TextStyle(fontSize: 17)),
            const SizedBox(height: 12),
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _presetBackgrounds.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  return GestureDetector(
                    onTap: () => setState(() => _bgIndex = i),
                    child: Container(
                      width: 80,
                      decoration: BoxDecoration(
                        gradient: _presetBackgrounds[i].gradient,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: i == _bgIndex ? Colors.blue : Colors.transparent, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          _presetBackgrounds[i].name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _start,
                child: const Text('はじめる'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PresetBackground {
  final String name;
  final Gradient gradient;
  const PresetBackground(this.name, this.gradient);
}

const _presetBackgrounds = <PresetBackground>[
  PresetBackground('春', LinearGradient(colors: [Color(0xFFFA709A), Color(0xFFFEE140)])),
  PresetBackground('夏', LinearGradient(colors: [Color(0xFF00C6FF), Color(0xFF0072FF)])),
  PresetBackground('秋', LinearGradient(colors: [Color(0xFFF7971E), Color(0xFFFFD200)])),
  PresetBackground('冬', LinearGradient(colors: [Color(0xFF83a4d4), Color(0xFFb6fbff)])),
  PresetBackground('和紙', LinearGradient(colors: [Color(0xFFB993D6), Color(0xFF8CA6DB)])),
  PresetBackground('宇宙', LinearGradient(colors: [Color(0xFF0F2027), Color(0xFF2C5364)])),
  PresetBackground('深海', LinearGradient(colors: [Color(0xFF000428), Color(0xFF004e92)])),
  PresetBackground('木漏れ日', LinearGradient(colors: [Color(0xFF56ab2f), Color(0xFFA8E063)])),
  PresetBackground('夜景', LinearGradient(colors: [Color(0xFF434343), Color(0xFF000000)])),
  PresetBackground('苔庭', LinearGradient(colors: [Color(0xFF11998e), Color(0xFF38ef7d)])),
  PresetBackground('雪', LinearGradient(colors: [Color(0xFFe6dada), Color(0xFF274046)])),
];
