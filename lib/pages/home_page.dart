import 'dart:io';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:audioplayers/audioplayers.dart';

import '../growth_logic.dart';
import '../models.dart';
import '../notification_service.dart';
import '../storage.dart';
import 'package:uuid/uuid.dart';
import '../tank_items.dart';
import '../marimo_comments.dart';
import '../backgrounds.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  Marimo? _marimo;
  UserSetting? _settings;
  int _bgIndex = 0;
  List<TankItem> _items = [];
  final engine = GrowthEngine();

  // Physics state (alignment space [-1,1])
  Offset _pos = const Offset(0, -0.9); // start near top
  Offset _vel = Offset.zero;
  Offset _grav = Offset.zero; // gravity vector from tilt, normalized [-1,1]
  late final Ticker _ticker;
  DateTime? _lastTick;
  StreamSubscription? _accelSub;
  StreamSubscription? _userAccelSub;
  // Floating animation (small drift) when enabled and daytime
  double _floatTime = 0.0;
  Offset _floatOffset = Offset.zero;
  // Water change wave effect state
  bool _waveActive = false;
  double _waveProgress = 0.0; // 0..1
  String? _speechText; // marimo speech bubble text
  Timer? _speechTimer;
  // Audio player for SFX
  final AudioPlayer _sfxPlayer = AudioPlayer();
  void _log(Object msg) {
    // legacy logger for debugging; kept minimal
    // ignore: avoid_print
    print('[Home] $msg');
  }

  // First-run tutorial
  bool _showTutorial = false;
  int _tutorialStep = 0;

  DateTime _now() {
    final s = _settings;
    return (s?.debugNowOverride) ?? DateTime.now();
  }

  bool get _photosynthesisActive =>
      (_settings?.floatingEnabled ?? true) && _isDaytime(_now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    // Prefer accelerometer (includes gravity); fallback to user accelerometer
    _accelSub = accelerometerEventStream().listen((e) {
      final dxNorm = (-e.x / 9.8).clamp(-1.0, 1.0);
      final dyNorm = (e.y / 9.8).clamp(-1.0, 1.0);
      _grav = Offset(dxNorm.toDouble(), dyNorm.toDouble());
    }, onError: (_) {
      _userAccelSub = userAccelerometerEventStream().listen((e) {
        final dxNorm = (-e.x / 9.8).clamp(-1.0, 1.0);
        final dyNorm = (e.y / 9.8).clamp(-1.0, 1.0);
        _grav = Offset(dxNorm.toDouble(), dyNorm.toDouble());
      });
    });
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final now = DateTime.now();
    double dt = 0.0;
    if (_lastTick != null) {
      dt = now.difference(_lastTick!).inMicroseconds / 1e6;
    }
    _lastTick = now;
    if (dt <= 0) return;
    dt = dt.clamp(0.0, 1 / 30); // clamp long frames

    // Tuned for slower movement
    const double accelStrength = 0.8; // alignment units per second^2 per 1g
    const double frictionPerSecond = 0.85; // velocity retention per second
    const double bounce = 0.2; // velocity retained after hitting wall
    const double limit = 0.92; // keep margin from edges

    // Integrate
    _vel = Offset(
      _vel.dx + _grav.dx * accelStrength * dt,
      _vel.dy + _grav.dy * accelStrength * dt,
    );
    final friction = math.pow(frictionPerSecond, dt).toDouble();
    _vel = _vel * friction;
    var next = Offset(_pos.dx + _vel.dx * dt, _pos.dy + _vel.dy * dt);

    // Collide with bounds and bounce
    if (next.dx < -limit) {
      next = Offset(-limit, next.dy);
      _vel = Offset(-_vel.dx * bounce, _vel.dy);
    } else if (next.dx > limit) {
      next = Offset(limit, next.dy);
      _vel = Offset(-_vel.dx * bounce, _vel.dy);
    }
    if (next.dy < -limit) {
      next = Offset(next.dx, -limit);
      _vel = Offset(_vel.dx, -_vel.dy * bounce);
    } else if (next.dy > limit) {
      next = Offset(next.dx, limit);
      _vel = Offset(_vel.dx, -_vel.dy * bounce);
    }

    _pos = next;

    // Floating drift update (tiny sinusoidal)
    if ((_settings?.floatingEnabled ?? true) && _isDaytime(now)) {
      _floatTime += dt;
      final fx =
          math.sin(_floatTime * 0.6) * 0.06; // amplitude in alignment units
      final fy = math.cos(_floatTime * 0.8) * 0.06;
      _floatOffset = Offset(fx, fy);
    } else {
      _floatOffset = Offset.zero;
    }
    // Wave effect progress
    if (_waveActive) {
      _waveProgress += dt / 1.2; // animate ~1.2s
      if (_waveProgress >= 1.0) {
        _waveActive = false;
        _waveProgress = 0.0;
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accelSub?.cancel();
    _userAccelSub?.cancel();
    _ticker.dispose();
    _speechTimer?.cancel();
    _sfxPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // On foreground resume, refresh data and apply any pending growth
      _load();
    }
  }

  Future<void> _load() async {
    final m = await AppStorage.instance.loadMarimo();
    final logs = await AppStorage.instance.loadLogs();
    final items = await AppStorage.instance.loadItems();
    final s = await AppStorage.instance.loadSettings();
    setState(() {
      _settings = s;
      _marimo = m;
      _bgIndex = s.backgroundIndex;
      _items = items;
    });
    if (m == null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/setup');
      return;
    }
    // Apply growth ticks and schedule notifications
    final now = _now();
    final (updated, newLogs) =
        engine.applyDailyGrowth(marimo: m, now: now, existingLogs: logs);
    await AppStorage.instance.saveMarimo(updated);
    await AppStorage.instance.saveLogs(newLogs);
    setState(() {
      _marimo = updated;
    });
    await NotificationService.instance.scheduleWaterChangeReminders(
      lastWaterChangeAt: updated.lastWaterChangeAt,
      enabled: s.notificationsEnabled && updated.state == MarimoState.alive,
      nowOverride: _settings?.debugNowOverride,
    );
    // Show first-run tutorial if not shown before
    final shown = await AppStorage.instance.isTutorialShown();
    if (!shown && mounted) {
      setState(() {
        _tutorialStep = 0;
        _showTutorial = true;
      });
    }
  }

  // Removed old death dialog; using in-page overlay instead

  Future<void> _waterChange() async {
    if (_marimo == null) return;
    final now = _now();
    final last = _marimo!.lastWaterChangeAt;
    if (last != null) {
      final hours = now.difference(last).inHours;
      if (hours < 24) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('水換えはあと${24 - hours}時間後にできます')),
        );
        return;
      }
    }
    final updated = engine.applyWaterChange(marimo: _marimo!, now: now);
    await AppStorage.instance.saveMarimo(updated);
    setState(() => _marimo = updated);
    await _hapticLight();
    _startWaveEffect();
    unawaited(_playWaterSound());
    // Reschedule notifications after water change
    final settings = _settings ?? await AppStorage.instance.loadSettings();
    await NotificationService.instance.scheduleWaterChangeReminders(
      lastWaterChangeAt: updated.lastWaterChangeAt,
      enabled: settings.notificationsEnabled,
      nowOverride: _settings?.debugNowOverride,
    );
  }

  void _startWaveEffect() {
    _waveActive = true;
    _waveProgress = 0.0;
  }

  Future<void> _playWaterSound() async {
    try {
      await _sfxPlayer.play(AssetSource('sounds/water.wav'));
    } catch (_) {}
  }

  Future<void> _poke() async {
    if (_marimo == null) return;
    final updated = _marimo!.copyWith(lastInteractionAt: DateTime.now());
    await AppStorage.instance.saveMarimo(updated);
    setState(() => _marimo = updated);
    await _hapticSelection();
  }

  void _onMarimoTapped() {
    _poke();
    if (marimoComments.isEmpty) return;
    final i = math.Random().nextInt(marimoComments.length);
    final line = marimoComments[i];
    _speechTimer?.cancel();
    setState(() => _speechText = line);
    _speechTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _speechText = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = _marimo;
    if (m == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final sizePx =
        (m.sizeMm * 5).clamp(30.0, 240.0); // scale factor for display
    final cleanColor =
        Color.lerp(Colors.red, Colors.green, m.cleanliness / 100.0) ??
            Colors.green;
    final daysSinceStart = _daysSince(m.startedAt) + 1; // 1日目スタート
    final lastWaterAgo = m.lastWaterChangeAt == null
        ? null
        : _daysAgoLabel(m.lastWaterChangeAt!);
    final lastWaterLabel = (lastWaterAgo == null)
        ? '-'
        : '${_fmt(m.lastWaterChangeAt!)}（$lastWaterAgo）';

    return Scaffold(
      appBar: AppBar(
        title: Text(m.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.of(context).pushNamed('/settings');
              final s = await AppStorage.instance.loadSettings();
              if (!mounted) return;
              setState(() {
                _settings = s;
                _bgIndex = s.backgroundIndex;
              });
            },
          )
        ],
      ),
      body: Stack(
        children: [
          Container(
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                // Top summary panel
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                        color: _panelColor(),
                        borderRadius: BorderRadius.circular(12)),
                    child: DefaultTextStyle(
                      style: TextStyle(color: _panelTextColor(), fontSize: 16),
                      child: IconTheme(
                        data: IconThemeData(color: _panelTextColor()),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('育て始めて: $daysSinceStart日目'),
                            Text('サイズ: ${m.sizeMm.toStringAsFixed(2)}mm'),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('清潔度 '),
                                SizedBox(
                                  width: 120,
                                  child: LinearProgressIndicator(
                                    value: m.cleanliness / 100.0,
                                    color: cleanColor,
                                    backgroundColor: Colors.white24,
                                  ),
                                ),
                              ],
                            ),
                            Text('最終水換え: $lastWaterLabel'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Main tank area
                Expanded(
                  child: SizedBox.expand(
                    child: GestureDetector(
                      onTap: _poke,
                      child: Stack(
                        children: [
                          Positioned.fill(
                              child: Container(
                                  decoration: _backgroundDecoration())),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: _MurkinessLayer(
                                  level: 1.0 - (m.cleanliness / 100.0)),
                            ),
                          ),
                          ..._buildItemWidgets(front: false),
                          Align(
                            alignment: Alignment(
                              (_pos.dx + _floatOffset.dx).clamp(-0.98, 0.98),
                              (_pos.dy + _floatOffset.dy).clamp(-0.98, 0.98),
                            ),
                            child: GestureDetector(
                              onTap: _onMarimoTapped,
                              child: ColorFiltered(
                                colorFilter: ColorFilter.matrix(
                                  _brightnessMatrix(1.0 -
                                      0.3 * (1.0 - (m.cleanliness / 100.0))),
                                ),
                                child: _MarimoVisual(size: sizePx),
                              ),
                            ),
                          ),
                          ..._buildItemWidgets(front: true),
                          if (_speechText != null)
                            Align(
                              alignment: Alignment(
                                (_pos.dx + _floatOffset.dx).clamp(-0.98, 0.98),
                                (_pos.dy + _floatOffset.dy).clamp(-0.98, 0.98),
                              ),
                              child: Transform.translate(
                                offset: Offset(0, -sizePx * 0.75 - 24),
                                child: AnimatedOpacity(
                                  opacity: 1.0,
                                  duration: const Duration(milliseconds: 180),
                                  child: Container(
                                    constraints:
                                        const BoxConstraints(maxWidth: 240),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.92),
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: const [
                                        BoxShadow(
                                            color: Colors.black26,
                                            blurRadius: 8,
                                            offset: Offset(0, 3)),
                                      ],
                                    ),
                                    child: Text(
                                      _speechText!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Colors.black87,
                                          fontSize: 14,
                                          height: 1.2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (_waveActive)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _WaterWavePainter(
                                      progress: _waveProgress,
                                      isBrightBg: _isBackgroundBright()),
                                ),
                              ),
                            ),
                          if (_photosynthesisActive)
                            Positioned(
                              top: 8,
                              left: 8,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 250),
                                opacity: 1.0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _isBackgroundBright()
                                        ? Colors.black.withOpacity(0.45)
                                        : Colors.white.withOpacity(0.8),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.wb_sunny,
                                        size: 16,
                                        color: _isBackgroundBright()
                                            ? Colors.white
                                            : Colors.orange.shade700,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '光合成中',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: _isBackgroundBright()
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Bottom action bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                        color: _panelColor(),
                        borderRadius: BorderRadius.circular(16)),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _onAddItemPressed,
                          icon: Icon(Icons.add, color: _outlineColor()),
                          label: Text('アイテム追加',
                              style: TextStyle(
                                  color: _outlineColor(), fontSize: 16)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: _outlineColor()),
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _waterChange,
                          icon: Icon(Icons.water_drop, color: _primaryFg()),
                          label: Text('水換え',
                              style:
                                  TextStyle(color: _primaryFg(), fontSize: 16)),
                          style: FilledButton.styleFrom(
                            backgroundColor: _primaryBg(),
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (m.state == MarimoState.dead)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.all(20),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black26,
                            blurRadius: 12,
                            offset: Offset(0, 6))
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('💀', style: TextStyle(fontSize: 64)),
                        const SizedBox(height: 8),
                        const Text('まりもがいなくなってしまいました',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        Text('育てた日数: $daysSinceStart日間',
                            style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 8),
                        const Text('今まで大切に育ててくれてありがとう',
                            style: TextStyle(fontSize: 16)),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () async {
                            if (!mounted) return;
                            Navigator.of(context)
                                .pushReplacementNamed('/setup');
                          },
                          child: const Text('新しいまりもを育てる'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          _tutorialOverlay(),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) {
    final l = dt.toLocal();
    return '${l.month}/${l.day} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  bool _isDaytime(DateTime now) {
    final h = now.hour;
    return h >= 7 && h < 19; // 7:00-18:59 considered daytime
  }

  Future<void> _hapticLight() async {
    if (_settings?.haptics ?? true) {
      try {
        await HapticFeedback.lightImpact();
      } catch (_) {}
    }
  }

  Future<void> _hapticSelection() async {
    if (_settings?.haptics ?? true) {
      try {
        await HapticFeedback.selectionClick();
      } catch (_) {}
    }
  }

  int _daysSince(DateTime since) {
    final a = _now().toLocal();
    final b = since.toLocal();
    final ad = DateTime(a.year, a.month, a.day);
    final bd = DateTime(b.year, b.month, b.day);
    return ad.difference(bd).inDays;
  }

  String _daysAgoLabel(DateTime time) {
    final days = _daysSince(time);
    if (days <= 0) return '今日';
    if (days == 1) return '1日前';
    return '$days日前';
  }

  BoxDecoration _backgroundDecoration() {
    final custom = _settings?.customBackgroundPath;
    if (custom != null && custom.isNotEmpty) {
      final file = File(custom);
      if (file.existsSync()) {
        return BoxDecoration(
          image: DecorationImage(
              image: FileImage(file),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high),
        );
      }
    }
    return BoxDecoration(
        gradient:
            presetBackgrounds[_bgIndex % presetBackgrounds.length].gradient);
  }

  // Brightness color matrix for ColorFiltered
  List<double> _brightnessMatrix(double b) {
    // Clamp and return a 5x4 color matrix that scales RGB by b (alpha unchanged)
    final bb = b.clamp(0.0, 1.5);
    return <double>[
      bb,
      0,
      0,
      0,
      0,
      0,
      bb,
      0,
      0,
      0,
      0,
      0,
      bb,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  bool _isBackgroundBright() {
    final custom = _settings?.customBackgroundPath;
    if (custom != null && custom.isNotEmpty) {
      // Unknown; assume bright so we use dark panel
      return true;
    }
    final bg = presetBackgrounds[_bgIndex % presetBackgrounds.length];
    if (bg.gradient is LinearGradient) {
      final g = bg.gradient as LinearGradient;
      final avg =
          Color.lerp(g.colors.first, g.colors.last, 0.5) ?? g.colors.first;
      return avg.computeLuminance() > 0.5;
    }
    return true;
  }

  Color _panelColor() => _isBackgroundBright()
      ? Colors.black.withOpacity(0.38)
      : Colors.white.withOpacity(0.35);
  Color _panelTextColor() =>
      _isBackgroundBright() ? Colors.white : Colors.black;
  Color _primaryBg() =>
      _panelTextColor() == Colors.white ? Colors.white : Colors.black87;
  Color _primaryFg() =>
      _panelTextColor() == Colors.white ? Colors.black : Colors.white;
  Color _outlineColor() => _panelTextColor().withOpacity(0.9);

  Widget _tutorialOverlay() {
    if (!_showTutorial) return const SizedBox.shrink();
    final steps = [
      ('ようこそ！', '端末を傾けるとまりもが動きます。\nタップで反応します。日中はゆっくり漂います。'),
      ('水換えとアイテム', '下部の「水換え」ボタンで清潔度UP。\n「アイテム追加」で水槽にパーツを置けます。'),
      ('お手入れの注意', '水換えをしない日が続くと水槽が濁っていきます。\n10日間放置すると、まりもがいなくなってしまうことがあります。'),
      ('アイテムの編集', 'ピンチ操作で移動・拡大縮小・回転。\n長押しで「削除/前後移動」を選べます。設定から背景変更も可能。'),
    ];
    final (title, message) = steps[_tutorialStep];
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Container(
          color: Colors.black54,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Material(
                color: Colors.white,
                elevation: 6,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Text(message,
                          style: const TextStyle(fontSize: 16, height: 1.4)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () async {
                              await AppStorage.instance.setTutorialShown(true);
                              if (mounted)
                                setState(() => _showTutorial = false);
                            },
                            child: const Text('スキップ'),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: () async {
                              final lastStep = steps.length - 1;
                              if (_tutorialStep < lastStep) {
                                setState(() => _tutorialStep += 1);
                              } else {
                                await AppStorage.instance
                                    .setTutorialShown(true);
                                if (mounted)
                                  setState(() => _showTutorial = false);
                              }
                            },
                            child: Text(_tutorialStep < (steps.length - 1)
                                ? '次へ'
                                : 'はじめる'),
                          )
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildItemWidgets({required bool front}) {
    return _items
        .where((it) => it.front == front)
        .map<Widget>((it) => _TankItemWidget(
              key: ValueKey(it.id),
              item: it,
              onChanged: (updated) async {
                final idx = _items.indexWhere((e) => e.id == updated.id);
                if (idx >= 0) {
                  setState(() => _items[idx] = updated);
                  await AppStorage.instance.saveItems(_items);
                }
              },
              onDelete: () async {
                setState(() => _items.removeWhere((e) => e.id == it.id));
                await AppStorage.instance.saveItems(_items);
              },
            ))
        .toList();
  }

  Future<void> _onAddItemPressed() async {
    final type = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _ItemGallery()),
    );
    if (type == null) return;
    final id = const Uuid().v4();
    final scale = TankItemRegistry.defaultScaleOf(type);
    final newItem = TankItem(
      id: id,
      type: type,
      x: 0.0,
      y: 0.7, // near bottom by default
      scale: scale,
      rotation: 0.0,
      front: true, // initially in front for easy manipulation
    );
    setState(() => _items = [..._items, newItem]);
    await AppStorage.instance.saveItems(_items);
    await _hapticSelection();
  }
}

class _TankItemWidget extends StatefulWidget {
  final TankItem item;
  final ValueChanged<TankItem> onChanged;
  final VoidCallback onDelete;

  const _TankItemWidget(
      {super.key,
      required this.item,
      required this.onChanged,
      required this.onDelete});

  @override
  State<_TankItemWidget> createState() => _TankItemWidgetState();
}

class _TankItemWidgetState extends State<_TankItemWidget> {
  double? _startScale;
  double? _startRotation;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth == double.infinity
            ? MediaQuery.of(context).size.width
            : constraints.maxWidth;
        final height = constraints.maxHeight == double.infinity
            ? MediaQuery.of(context).size.height
            : constraints.maxHeight;

        return Align(
          alignment:
              Alignment(item.x.clamp(-1.0, 1.0), item.y.clamp(-1.0, 1.0)),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (_) {
              _startScale = item.scale;
              _startRotation = item.rotation;
            },
            onScaleUpdate: (details) {
              final baseScale = _startScale ?? item.scale;
              final baseRot = _startRotation ?? item.rotation;
              final newScale = (baseScale * details.scale).clamp(0.3, 4.0);
              final newRot = baseRot + details.rotation;
              // Also handle translation via focalPointDelta during scale gesture
              if (width > 0 && height > 0) {
                final dx = (details.focalPointDelta.dx / width) * 2.0;
                final dy = (details.focalPointDelta.dy / height) * 2.0;
                final nx = (item.x + dx).clamp(-1.0, 1.0);
                final ny = (item.y + dy).clamp(-1.0, 1.0);
                widget.onChanged(item.copyWith(
                    x: nx, y: ny, scale: newScale, rotation: newRot));
              } else {
                widget.onChanged(
                    item.copyWith(scale: newScale, rotation: newRot));
              }
            },
            onDoubleTap: () {
              // Toggle front/back on double tap
              widget.onChanged(item.copyWith(front: !item.front));
            },
            onLongPress: () async {
              // Simple context actions: delete or toggle layer
              final action = await showModalBottomSheet<String>(
                context: context,
                builder: (context) {
                  return SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.flip_to_front),
                          title: Text(item.front ? '後ろに移動' : '前に移動'),
                          onTap: () =>
                              Navigator.of(context).pop('toggle_layer'),
                        ),
                        const Divider(height: 0),
                        ListTile(
                          leading: const Icon(Icons.delete, color: Colors.red),
                          title: const Text('削除',
                              style: TextStyle(color: Colors.red)),
                          onTap: () => Navigator.of(context).pop('delete'),
                        ),
                      ],
                    ),
                  );
                },
              );
              if (action == 'delete') {
                widget.onDelete();
              } else if (action == 'toggle_layer') {
                widget.onChanged(item.copyWith(front: !item.front));
              }
            },
            child: Transform.rotate(
              angle: item.rotation,
              child: Transform.scale(
                scale: item.scale.clamp(0.2, 4.0),
                child: TankItemRegistry.visualFor(context, item),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ItemGallery extends StatelessWidget {
  const _ItemGallery();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TankItemSpec>>(
      future: TankItemRegistry.loadSvgSpecs(),
      builder: (context, snapshot) {
        final specs = snapshot.data ?? const <TankItemSpec>[];
        return Scaffold(
          appBar: AppBar(title: const Text('アイテムを追加')),
          body: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: specs.length,
            itemBuilder: (context, i) {
              final s = specs[i];
              return InkWell(
                onTap: () => Navigator.of(context).pop(s.type),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: s.previewBuilder(context),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _WaterWavePainter extends CustomPainter {
  final double progress; // 0..1
  final bool isBrightBg;
  _WaterWavePainter({required this.progress, required this.isBrightBg});

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress;
    // Two layered waves moving upwards with fade out
    final baseColor =
        isBrightBg ? const Color(0xAAFFFFFF) : const Color(0x55FFFFFF);
    final wave1 = Paint()
      ..color = baseColor
      ..style = PaintingStyle.fill;
    final wave2 = Paint()
      ..color = baseColor.withOpacity((0.6 * (1 - t)).clamp(0, 1))
      ..style = PaintingStyle.fill;

    final amp = size.height * 0.03 * (1 - t); // decreasing amplitude
    final yOffset = size.height * (1 - t); // wave rises up

    Path makeWave(double phase, double scale) {
      final path = Path();
      path.moveTo(0, size.height);
      path.lineTo(0, yOffset);
      final steps = 40;
      for (int i = 0; i <= steps; i++) {
        final x = size.width * i / steps;
        final y =
            yOffset + math.sin((i / steps * 2 * math.pi) + phase) * amp * scale;
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.close();
      return path;
    }

    canvas.drawPath(makeWave(0 + t * 2 * math.pi, 1.0), wave1);
    canvas.drawPath(makeWave(math.pi / 2 + t * 2.4 * math.pi, 0.6), wave2);
  }

  @override
  bool shouldRepaint(covariant _WaterWavePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.isBrightBg != isBrightBg;
}

class _MarimoVisual extends StatelessWidget {
  final double size;
  const _MarimoVisual({required this.size});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 8))
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/marimo.PNG',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class _MurkinessLayer extends StatelessWidget {
  final double level; // 0.0 (clean) .. 1.0 (very murky)
  const _MurkinessLayer({required this.level});

  @override
  Widget build(BuildContext context) {
    if (level <= 0) return const SizedBox.shrink();
    // Cap opacity for aesthetics
    final tintOpacity = (0.18 * level).clamp(0.0, 0.35);
    return Stack(
      children: [
        // Subtle color tint towards green-brown to imply murky water
        Positioned.fill(
          child: Container(
              color: const Color(0xFF26332F).withOpacity(tintOpacity)),
        ),
        // Floating particles
        Positioned.fill(
          child: CustomPaint(
            painter: _MurkinessPainter(level: level),
          ),
        ),
      ],
    );
  }
}

class _MurkinessPainter extends CustomPainter {
  final double level;
  _MurkinessPainter({required this.level});

  @override
  void paint(Canvas canvas, Size size) {
    final int count = (20 + level * 120).toInt();
    final rnd = math.Random(123456); // deterministic positions
    final Paint p = Paint()
      ..color = const Color(0xFF8D6E63).withOpacity(0.08 + 0.22 * level)
      ..isAntiAlias = true;
    for (int i = 0; i < count; i++) {
      final dx = rnd.nextDouble() * size.width;
      final dy = rnd.nextDouble() * size.height;
      final r = (1.0 + rnd.nextDouble() * 2.5) * (0.5 + level);
      canvas.drawCircle(Offset(dx, dy), r, p);
    }
    // Light vertical streaks to suggest algae film
    final streakPaint = Paint()
      ..color = const Color(0xFF4E4E4E).withOpacity(0.04 * level)
      ..strokeWidth = 2.0
      ..isAntiAlias = true;
    final streaks = (size.width / 40).toInt();
    for (int s = 0; s < streaks; s++) {
      final x = (s * 40.0) + (rnd.nextDouble() * 20 - 10);
      canvas.drawLine(Offset(x, 0), Offset(x + 6, size.height), streakPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MurkinessPainter oldDelegate) {
    // Repaint if level changes
    return oldDelegate.level != level;
  }
}

// Removed old background gallery logic now migrated to SettingsPage
