import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert' show jsonDecode;
import 'package:flutter_svg/flutter_svg.dart';

import 'models.dart';

class TankItemSpec {
  final String type;
  final Widget Function(BuildContext context) previewBuilder;
  final Widget Function(BuildContext context, TankItem item) visualBuilder;
  final double defaultScale;
  const TankItemSpec({
    required this.type,
    required this.previewBuilder,
    required this.visualBuilder,
    this.defaultScale = 1.0,
  });
}

class TankItemRegistry {
  static final Map<String, TankItemSpec> _specs = {};
  static bool _loaded = false;

  static List<TankItemSpec> all() => _specs.values.toList();
  static TankItemSpec? specOf(String type) => _specs[type];

  static Future<List<TankItemSpec>> loadSvgSpecs() async {
    if (_loaded) return all();
    final manifestStr = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifest = jsonDecode(manifestStr) as Map<String, dynamic>;
    final keys = manifest.keys
        .where((k) => k.startsWith('assets/items/') && k.endsWith('.svg'))
        .toList()
      ..sort();
    for (final path in keys) {
      final spec = TankItemSpec(
        type: path,
        previewBuilder: (context) => SvgPicture.asset(path, width: 48, height: 48, fit: BoxFit.contain),
        visualBuilder: (context, item) => SvgPicture.asset(path, width: 64, height: 64, fit: BoxFit.contain),
        defaultScale: _inferDefaultScale(path),
      );
      _specs[path] = spec;
    }
    _loaded = true;
    return all();
  }

  static Widget visualFor(BuildContext context, TankItem item) {
    // If item.type is an SVG asset path, render it directly
    if (item.type.endsWith('.svg') && item.type.startsWith('assets/items/')) {
      return SvgPicture.asset(item.type, width: 64, height: 64, fit: BoxFit.contain);
    }
    final spec = _specs[item.type];
    if (spec != null) return spec.visualBuilder(context, item);
    return const Icon(Icons.circle, size: 32, color: Colors.white70);
  }

  static double defaultScaleOf(String type) {
    if (_specs.containsKey(type)) return _specs[type]!.defaultScale;
    if (type.endsWith('.svg')) return _inferDefaultScale(type);
    return 1.0;
  }

  static double _inferDefaultScale(String path) {
    // Heuristics: terrain/rock slightly larger default scale
    if (path.contains('terrain') || path.contains('rock')) return 1.4;
    if (path.contains('seaweed')) return 1.2;
    return 1.0;
  }
}

// legacy helper removed
