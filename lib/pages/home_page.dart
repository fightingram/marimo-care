import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

import '../growth_logic.dart';
import '../models.dart';
import '../notification_service.dart';
import '../storage.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../tank_items.dart';
import '../marimo_comments.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  Marimo? _marimo;
  List<GrowthLog> _logs = [];
  UserSetting? _settings;
  int _bgIndex = 0;
  List<TankItem> _items = [];
  final engine = GrowthEngine();
  final _repaintBoundaryKey = GlobalKey();

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
  bool _isCapturing = false;
  String? _speechText; // marimo speech bubble text
  Timer? _speechTimer;

  @override
  void initState() {
    super.initState();
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
      final fx = math.sin(_floatTime * 0.6) * 0.06; // amplitude in alignment units
      final fy = math.cos(_floatTime * 0.8) * 0.06;
      _floatOffset = Offset(fx, fy);
    } else {
      _floatOffset = Offset.zero;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _userAccelSub?.cancel();
    _ticker.dispose();
    _speechTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final m = await AppStorage.instance.loadMarimo();
    final logs = await AppStorage.instance.loadLogs();
    final items = await AppStorage.instance.loadItems();
    final s = await AppStorage.instance.loadSettings();
    setState(() {
      _settings = s;
      _logs = logs;
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
    final now = DateTime.now();
    final (updated, newLogs) = engine.applyDailyGrowth(marimo: m, now: now, existingLogs: logs);
    await AppStorage.instance.saveMarimo(updated);
    await AppStorage.instance.saveLogs(newLogs);
    setState(() {
      _marimo = updated;
      _logs = newLogs;
    });
    await NotificationService.instance.scheduleWaterChangeReminders(
      lastWaterChangeAt: updated.lastWaterChangeAt,
      enabled: s.notificationsEnabled,
    );
    if (updated.state == MarimoState.dead) {
      _showDeathDialog();
    }
  }

  void _showDeathDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('まりもが死んでしまいました'),
        content: const Text('水槽をリセットして、また育ててあげてください。'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('記録を見る'),
          ),
          FilledButton(
            onPressed: () async {
              final now = DateTime.now();
              final m = _marimo!;
              final reset = Marimo(
                id: m.id,
                name: m.name,
                state: MarimoState.alive,
                sizeMm: 5.0,
                cleanliness: 100,
                startedAt: now,
                lastWaterChangeAt: now,
                lastGrowthTickAt: DateTime(now.year, now.month, now.day),
                lastInteractionAt: now,
                waterBoostUntil: null,
              );
              await AppStorage.instance.saveMarimo(reset);
              if (!mounted) return;
              Navigator.of(context).pop();
              setState(() => _marimo = reset);
            },
            child: const Text('新しいまりもでリスタート'),
          ),
        ],
      ),
    );
  }

  Future<void> _waterChange() async {
    if (_marimo == null) return;
    final now = DateTime.now();
    final hours = now.difference(_marimo!.lastWaterChangeAt).inHours;
    if (hours < 24) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('水換えはあと${24 - hours}時間後にできます')),
      );
      return;
    }
    final updated = engine.applyWaterChange(marimo: _marimo!, now: now);
    await AppStorage.instance.saveMarimo(updated);
    setState(() => _marimo = updated);
    await _hapticLight();
    // Reschedule notifications after water change
    final settings = _settings ?? await AppStorage.instance.loadSettings();
    await NotificationService.instance.scheduleWaterChangeReminders(
      lastWaterChangeAt: updated.lastWaterChangeAt,
      enabled: settings.notificationsEnabled,
    );
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

    final sizePx = (m.sizeMm * 5).clamp(30.0, 240.0); // scale factor for display
    final cleanColor = Color.lerp(Colors.red, Colors.green, m.cleanliness / 100.0) ?? Colors.green;
    final daysSinceStart = _daysSince(m.startedAt) + 1; // 1日目スタート
    final lastWaterAgo = _daysAgoLabel(m.lastWaterChangeAt);

    return Scaffold(
      appBar: AppBar(
        title: Text(m.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          )
        ],
      ),
      body: Stack(
        children: [
          Container(
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: _panelColor(), borderRadius: BorderRadius.circular(12)),
                    child: DefaultTextStyle(
                      style: TextStyle(color: _panelTextColor(), fontSize: 16),
                      child: IconTheme(
                        data: IconThemeData(color: _panelTextColor()),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('育て始めて: ${daysSinceStart}日目'),
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
                            Text('最終水換え: ${_fmt(m.lastWaterChangeAt)}（${lastWaterAgo}）'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: RepaintBoundary(
                    key: _repaintBoundaryKey,
                    child: SizedBox.expand(
                      child: GestureDetector(
                        onTap: _poke,
                        onPanUpdate: (_) => _poke(),
                        child: Stack(
                          children: [
                            // Background inside boundary so screenshots include it
                        Positioned.fill(child: Container(decoration: _backgroundDecoration())),
                        // Items behind marimo
                        ..._buildItemWidgets(front: false),
                        Align(
                          alignment: Alignment(
                            (_pos.dx + _floatOffset.dx).clamp(-0.98, 0.98),
                            (_pos.dy + _floatOffset.dy).clamp(-0.98, 0.98),
                          ),
                          child: GestureDetector(
                            onTap: _onMarimoTapped,
                            child: _MarimoVisual(size: sizePx),
                          ),
                        ),
                        // Items in front of marimo
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
                                  constraints: const BoxConstraints(maxWidth: 240),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.92),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: const [
                                      BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
                                    ],
                                  ),
                                  child: Text(
                                    _speechText!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.black87, fontSize: 14, height: 1.2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: _panelColor(), borderRadius: BorderRadius.circular(16)),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _onAddItemPressed,
                      icon: Icon(Icons.add, color: _outlineColor()),
                      label: Text('アイテム追加', style: TextStyle(color: _outlineColor(), fontSize: 16)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: _outlineColor()),
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _waterChange,
                      icon: Icon(Icons.water_drop, color: _primaryFg()),
                      label: Text('水換え', style: TextStyle(color: _primaryFg(), fontSize: 16)),
                      style: FilledButton.styleFrom(
                        backgroundColor: _primaryBg(),
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final res = await Navigator.of(context).push<_BgResult>(
                          MaterialPageRoute(builder: (_) => const _BackgroundGallery()),
                        );
                        if (res != null) {
                          if (res.isCustom) {
                            // Reload settings from storage to get the newly saved custom path
                            final s = await AppStorage.instance.loadSettings();
                            setState(() => _settings = s);
                            // mark interaction
                            final m = _marimo; if (m != null) {
                              final updated = m.copyWith(lastInteractionAt: DateTime.now());
                              await AppStorage.instance.saveMarimo(updated);
                              setState(() => _marimo = updated);
                            }
                          } else {
                            setState(() => _bgIndex = res.index!);
                            final s = _settings ?? await AppStorage.instance.loadSettings();
                            s.backgroundIndex = res.index!;
                            s.customBackgroundPath = null;
                            await AppStorage.instance.saveSettings(s);
                            setState(() => _settings = s);
                            // mark interaction
                            final m = _marimo; if (m != null) {
                              final updated = m.copyWith(lastInteractionAt: DateTime.now());
                              await AppStorage.instance.saveMarimo(updated);
                              setState(() => _marimo = updated);
                            }
                          }
                          await _hapticSelection();
                        }
                      },
                      icon: Icon(Icons.image, color: _outlineColor()),
                      label: Text('背景変更', style: TextStyle(color: _outlineColor(), fontSize: 16)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: _outlineColor()),
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isCapturing ? null : _shareScreenshot,
                      icon: Icon(Icons.share, color: _outlineColor()),
                      label: Text('シェア', style: TextStyle(color: _outlineColor(), fontSize: 16)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: _outlineColor()),
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          if (_isCapturing)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: false,
                child: Container(
                  color: Colors.black38,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('画像を作成中...', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _shareScreenshot() async {
    try {
      setState(() => _isCapturing = true);
      // Ensure boundary is painted
      final boundary = _repaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('boundary not found');
      if (boundary.debugNeedsPaint) {
        await Future.delayed(const Duration(milliseconds: 20));
        await WidgetsBinding.instance.endOfFrame;
      }
      final devicePR = MediaQuery.of(context).devicePixelRatio;
      final pixelRatio = (devicePR * 2.0).clamp(2.0, 4.0);
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      // Optionally add watermark to the captured image
      Uint8List bytes;
      if ((_settings?.screenshotWatermark ?? true)) {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        final w = image.width.toDouble();
        final h = image.height.toDouble();
        // Draw original image
        canvas.drawImage(image, const Offset(0, 0), Paint());
        // Prepare watermark text
        const label = 'Marimochi';
        final tp = TextPainter(
          text: const TextSpan(style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w600), text: label),
          textDirection: TextDirection.ltr,
        )..layout();
        const pad = 16.0;
        const margin = 24.0;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(w - tp.width - pad * 2 - margin, h - tp.height - pad * 2 - margin, tp.width + pad * 2, tp.height + pad * 2),
          const Radius.circular(10),
        );
        final bg = Paint()..color = Colors.black54;
        canvas.drawRRect(rect, bg);
        tp.paint(canvas, Offset(w - tp.width - pad - margin, h - tp.height - pad - margin));
        // Finish and extract bytes
        final picture = recorder.endRecording();
        final watermarked = await picture.toImage(image.width, image.height);
        final byteData = await watermarked.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) return;
        bytes = byteData.buffer.asUint8List();
      } else {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) return;
        bytes = byteData.buffer.asUint8List();
      }
      final name = 'marimo_${DateTime.now().millisecondsSinceEpoch}.png';
      final result = await ImageGallerySaver.saveImage(
        bytes,
        name: name,
        isReturnImagePathOfIOS: true,
        quality: 100,
      );
      if (!mounted) return;
      final ok = (result is Map) ? (result['isSuccess'] == true || result['filePath'] != null) : true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'ライブラリに保存しました' : '保存に失敗しました')),
      );
      await _hapticLight();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('スクショの作成に失敗しました')));
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
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
    final a = DateTime.now().toLocal();
    final b = since.toLocal();
    final ad = DateTime(a.year, a.month, a.day);
    final bd = DateTime(b.year, b.month, b.day);
    return ad.difference(bd).inDays;
  }

  String _daysAgoLabel(DateTime time) {
    final days = _daysSince(time);
    if (days <= 0) return '今日';
    if (days == 1) return '1日前';
    return '${days}日前';
  }

  BoxDecoration _backgroundDecoration() {
    final custom = _settings?.customBackgroundPath;
    if (custom != null && custom.isNotEmpty) {
      final file = File(custom);
      if (file.existsSync()) {
        return BoxDecoration(
          image: DecorationImage(image: FileImage(file), fit: BoxFit.cover, filterQuality: FilterQuality.high),
        );
      }
    }
    return BoxDecoration(gradient: _presetBackgrounds[_bgIndex % _presetBackgrounds.length].gradient);
  }

  bool _isBackgroundBright() {
    final custom = _settings?.customBackgroundPath;
    if (custom != null && custom.isNotEmpty) {
      // Unknown; assume bright so we use dark panel
      return true;
    }
    final bg = _presetBackgrounds[_bgIndex % _presetBackgrounds.length];
    if (bg.gradient is LinearGradient) {
      final g = bg.gradient as LinearGradient;
      final avg = Color.lerp(g.colors.first, g.colors.last, 0.5) ?? g.colors.first;
      return avg.computeLuminance() > 0.5;
    }
    return true;
  }

  Color _panelColor() => _isBackgroundBright() ? Colors.black.withOpacity(0.38) : Colors.white.withOpacity(0.35);
  Color _panelTextColor() => _isBackgroundBright() ? Colors.white : Colors.black;
  Color _primaryBg() => _panelTextColor() == Colors.white ? Colors.white : Colors.black87;
  Color _primaryFg() => _panelTextColor() == Colors.white ? Colors.black : Colors.white;
  Color _outlineColor() => _panelTextColor().withOpacity(0.9);

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
      front: false, // initially behind marimo
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

  const _TankItemWidget({super.key, required this.item, required this.onChanged, required this.onDelete});

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
        final width = constraints.maxWidth == double.infinity ? MediaQuery.of(context).size.width : constraints.maxWidth;
        final height = constraints.maxHeight == double.infinity ? MediaQuery.of(context).size.height : constraints.maxHeight;

        return Align(
          alignment: Alignment(item.x.clamp(-1.0, 1.0), item.y.clamp(-1.0, 1.0)),
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
                widget.onChanged(item.copyWith(x: nx, y: ny, scale: newScale, rotation: newRot));
              } else {
                widget.onChanged(item.copyWith(scale: newScale, rotation: newRot));
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
                          onTap: () => Navigator.of(context).pop('toggle_layer'),
                        ),
                        const Divider(height: 0),
                        ListTile(
                          leading: const Icon(Icons.delete, color: Colors.red),
                          title: const Text('削除', style: TextStyle(color: Colors.red)),
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
    final specs = TankItemRegistry.all();
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  s.previewBuilder(context),
                  const SizedBox(height: 6),
                  Text(s.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
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
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, 8))],
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

class _BgResult {
  final int? index; // preset index when not custom
  final bool isCustom;
  const _BgResult.preset(this.index) : isCustom = false;
  const _BgResult.custom() : index = null, isCustom = true;
}

class _BackgroundGallery extends StatelessWidget {
  const _BackgroundGallery();
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
        itemCount: _presetBackgrounds.length + 1,
        itemBuilder: (context, i) {
          if (i == _presetBackgrounds.length) {
            return GestureDetector(
              onTap: () async {
                final picker = ImagePicker();
                final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 4096, maxHeight: 4096);
                if (picked != null) {
                  final s = await AppStorage.instance.loadSettings();
                  s.customBackgroundPath = picked.path;
                  await AppStorage.instance.saveSettings(s);
                  if (context.mounted) Navigator.of(context).pop(const _BgResult.custom());
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
            onTap: () => Navigator.of(context).pop(_BgResult.preset(i)),
            child: Container(
              decoration: BoxDecoration(
                gradient: _presetBackgrounds[i].gradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  _presetBackgrounds[i].name,
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
