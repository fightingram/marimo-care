import 'package:flutter/material.dart';

import 'models.dart';

class TankItemSpec {
  final String type;
  final String label;
  final Widget Function(BuildContext context) previewBuilder;
  final Widget Function(BuildContext context, TankItem item) visualBuilder;
  final double defaultScale;
  const TankItemSpec({
    required this.type,
    required this.label,
    required this.previewBuilder,
    required this.visualBuilder,
    this.defaultScale = 1.0,
  });
}

class TankItemRegistry {
  static final Map<String, TankItemSpec> _specs = {
    'weed': TankItemSpec(
      type: 'weed',
      label: '水草',
      previewBuilder: (context) => Icon(Icons.grass, color: Colors.green.shade400, size: 28),
      visualBuilder: (context, item) => Icon(
        Icons.grass,
        size: 48,
        color: Colors.green.shade300,
        shadows: const [Shadow(color: Colors.black26, blurRadius: 6)],
      ),
      defaultScale: 1.0,
    ),
    'rock': TankItemSpec(
      type: 'rock',
      label: '岩',
      previewBuilder: (context) => Container(
        width: 26,
        height: 18,
        decoration: BoxDecoration(color: Colors.grey.shade600, borderRadius: BorderRadius.circular(10)),
      ),
      visualBuilder: (context, item) => Container(
        width: 40,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.grey.shade600,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))],
        ),
      ),
      defaultScale: 1.0,
    ),
    'bubbles': TankItemSpec(
      type: 'bubbles',
      label: '泡',
      previewBuilder: (context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _bubble(8), const SizedBox(width: 2), _bubble(10), const SizedBox(width: 2), _bubble(6),
        ],
      ),
      visualBuilder: (context, item) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _bubble(10), const SizedBox(width: 4), _bubble(14), const SizedBox(width: 4), _bubble(8),
        ],
      ),
      defaultScale: 1.0,
    ),
    'star': TankItemSpec(
      type: 'star',
      label: 'スター',
      previewBuilder: (context) => const Icon(Icons.star, color: Colors.amber, size: 24),
      visualBuilder: (context, item) => const Icon(Icons.star, color: Colors.amber, size: 36),
      defaultScale: 1.0,
    ),
    'shell': TankItemSpec(
      type: 'shell',
      label: '貝殻',
      previewBuilder: (context) => const Icon(Icons.beach_access, color: Colors.pinkAccent, size: 24),
      visualBuilder: (context, item) => const Icon(Icons.beach_access, color: Colors.pinkAccent, size: 34),
      defaultScale: 1.0,
    ),
    'wood': TankItemSpec(
      type: 'wood',
      label: '流木',
      previewBuilder: (context) => const Icon(Icons.park, color: Colors.brown, size: 24),
      visualBuilder: (context, item) => const Icon(Icons.park, color: Colors.brown, size: 34),
      defaultScale: 1.0,
    ),
  };

  static List<TankItemSpec> all() => _specs.values.toList();
  static TankItemSpec? specOf(String type) => _specs[type];
  static Widget visualFor(BuildContext context, TankItem item) {
    final spec = _specs[item.type];
    if (spec != null) return spec.visualBuilder(context, item);
    return const Icon(Icons.circle, size: 32, color: Colors.white70);
  }

  static double defaultScaleOf(String type) => _specs[type]?.defaultScale ?? 1.0;
}

Widget _bubble(double size) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white70,
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
    ),
  );
}
