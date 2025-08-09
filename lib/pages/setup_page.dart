import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../storage.dart';
import '../backgrounds.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _nameController = TextEditingController();
  int _bgIndex = 0;
  final FocusNode _nameFocus = FocusNode();

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
      // 初回は未実施扱い
      lastWaterChangeAt: null,
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
      appBar: AppBar(title: const Text('はじめに', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.black))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('まりもの名前を決めましょう', style: TextStyle(fontSize: 17)),
            TextField(
              controller: _nameController,
              focusNode: _nameFocus,
              autofocus: true,
              decoration: const InputDecoration(hintText: '例: まりもっち'),
            ),
            const SizedBox(height: 24),
            const Text('背景を選んでください（後で変更できます）', style: TextStyle(fontSize: 17)),
            const SizedBox(height: 12),
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: presetBackgrounds.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  return GestureDetector(
                    onTap: () => setState(() => _bgIndex = i),
                    child: Container(
                      width: 80,
                      decoration: BoxDecoration(
                        gradient: presetBackgrounds[i].gradient,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: i == _bgIndex ? Colors.blue : Colors.transparent, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          presetBackgrounds[i].name,
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

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }
}
