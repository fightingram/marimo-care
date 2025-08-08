import 'dart:convert';

enum MarimoState { alive, dead }

class Marimo {
  final String id;
  String name;
  MarimoState state;
  double sizeMm;
  int cleanliness; // 0..100
  DateTime startedAt;
  DateTime lastWaterChangeAt;
  DateTime lastGrowthTickAt;
  DateTime lastInteractionAt;
  DateTime? waterBoostUntil; // optional, for +k window

  Marimo({
    required this.id,
    required this.name,
    required this.state,
    required this.sizeMm,
    required this.cleanliness,
    required this.startedAt,
    required this.lastWaterChangeAt,
    required this.lastGrowthTickAt,
    required this.lastInteractionAt,
    this.waterBoostUntil,
  });

  Marimo copyWith({
    String? name,
    MarimoState? state,
    double? sizeMm,
    int? cleanliness,
    DateTime? startedAt,
    DateTime? lastWaterChangeAt,
    DateTime? lastGrowthTickAt,
    DateTime? lastInteractionAt,
    DateTime? waterBoostUntil,
  }) {
    return Marimo(
      id: id,
      name: name ?? this.name,
      state: state ?? this.state,
      sizeMm: sizeMm ?? this.sizeMm,
      cleanliness: cleanliness ?? this.cleanliness,
      startedAt: startedAt ?? this.startedAt,
      lastWaterChangeAt: lastWaterChangeAt ?? this.lastWaterChangeAt,
      lastGrowthTickAt: lastGrowthTickAt ?? this.lastGrowthTickAt,
      lastInteractionAt: lastInteractionAt ?? this.lastInteractionAt,
      waterBoostUntil: waterBoostUntil ?? this.waterBoostUntil,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'state': state.name,
        'sizeMm': sizeMm,
        'cleanliness': cleanliness,
        'startedAt': startedAt.toIso8601String(),
        'lastWaterChangeAt': lastWaterChangeAt.toIso8601String(),
        'lastGrowthTickAt': lastGrowthTickAt.toIso8601String(),
        'lastInteractionAt': lastInteractionAt.toIso8601String(),
        'waterBoostUntil': waterBoostUntil?.toIso8601String(),
      };

  static Marimo fromJson(Map<String, dynamic> json) {
    return Marimo(
      id: json['id'] as String,
      name: json['name'] as String,
      state: (json['state'] as String) == 'dead' ? MarimoState.dead : MarimoState.alive,
      sizeMm: (json['sizeMm'] as num).toDouble(),
      cleanliness: (json['cleanliness'] as num).toInt(),
      startedAt: DateTime.parse(json['startedAt'] as String),
      lastWaterChangeAt: DateTime.parse(json['lastWaterChangeAt'] as String),
      lastGrowthTickAt: DateTime.parse(json['lastGrowthTickAt'] as String),
      lastInteractionAt: DateTime.parse(json['lastInteractionAt'] as String),
      waterBoostUntil: json['waterBoostUntil'] == null
          ? null
          : DateTime.parse(json['waterBoostUntil'] as String),
    );
  }

  static String encode(Marimo m) => jsonEncode(m.toJson());
  static Marimo decode(String s) => fromJson(jsonDecode(s) as Map<String, dynamic>);
}

class GrowthLog {
  final DateTime date; // normalized to YYYY-MM-DD local
  final double deltaMm;
  final double sizeAfterMm;
  final int cleanlinessAfter;

  GrowthLog({
    required this.date,
    required this.deltaMm,
    required this.sizeAfterMm,
    required this.cleanlinessAfter,
  });

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'deltaMm': deltaMm,
        'sizeAfterMm': sizeAfterMm,
        'cleanlinessAfter': cleanlinessAfter,
      };

  static GrowthLog fromJson(Map<String, dynamic> json) => GrowthLog(
        date: DateTime.parse(json['date'] as String),
        deltaMm: (json['deltaMm'] as num).toDouble(),
        sizeAfterMm: (json['sizeAfterMm'] as num).toDouble(),
        cleanlinessAfter: (json['cleanlinessAfter'] as num).toInt(),
      );

  static String encodeList(List<GrowthLog> logs) => jsonEncode(logs.map((e) => e.toJson()).toList());
  static List<GrowthLog> decodeList(String s) =>
      (jsonDecode(s) as List).map((e) => GrowthLog.fromJson(e as Map<String, dynamic>)).toList();
}

class UserSetting {
  bool notificationsEnabled;
  bool screenshotWatermark;
  bool haptics;
  bool floatingEnabled; // 光合成・浮遊アニメON/OFF
  int backgroundIndex; // 背景プリセットのインデックス（0..10）
  String? customBackgroundPath; // 端末アルバム画像のパス（未使用時null）

  UserSetting({
    required this.notificationsEnabled,
    required this.screenshotWatermark,
    required this.haptics,
    required this.floatingEnabled,
    required this.backgroundIndex,
    this.customBackgroundPath,
  });

  Map<String, dynamic> toJson() => {
        'notificationsEnabled': notificationsEnabled,
        'screenshotWatermark': screenshotWatermark,
        'haptics': haptics,
        'floatingEnabled': floatingEnabled,
        'backgroundIndex': backgroundIndex,
        'customBackgroundPath': customBackgroundPath,
      };

  static UserSetting fromJson(Map<String, dynamic> json) => UserSetting(
        notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
        screenshotWatermark: json['screenshotWatermark'] as bool? ?? true,
        haptics: json['haptics'] as bool? ?? true,
        floatingEnabled: json['floatingEnabled'] as bool? ?? true,
        backgroundIndex: (json['backgroundIndex'] as num?)?.toInt() ?? 0,
        customBackgroundPath: json['customBackgroundPath'] as String?,
      );

  static String encode(UserSetting s) => jsonEncode(s.toJson());
  static UserSetting decode(String str) => fromJson(jsonDecode(str) as Map<String, dynamic>);
}

class TankItem {
  final String id;
  final String type; // e.g., 'weed', 'rock', 'bubbles', 'star'
  final double x; // alignment space -1..1
  final double y; // alignment space -1..1
  final double scale; // visual scale factor (0.5..3.0)
  final double rotation; // radians
  final bool front; // if true, render above marimo

  TankItem({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.scale,
    required this.rotation,
    required this.front,
  });

  TankItem copyWith({
    String? type,
    double? x,
    double? y,
    double? scale,
    double? rotation,
    bool? front,
  }) => TankItem(
        id: id,
        type: type ?? this.type,
        x: x ?? this.x,
        y: y ?? this.y,
        scale: scale ?? this.scale,
        rotation: rotation ?? this.rotation,
        front: front ?? this.front,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
        'front': front,
      };

  static TankItem fromJson(Map<String, dynamic> json) => TankItem(
        id: json['id'] as String,
        type: json['type'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        scale: (json['scale'] as num).toDouble(),
        rotation: (json['rotation'] as num).toDouble(),
        front: json['front'] as bool? ?? false,
      );

  static String encodeList(List<TankItem> items) => jsonEncode(items.map((e) => e.toJson()).toList());
  static List<TankItem> decodeList(String s) =>
      (jsonDecode(s) as List).map((e) => TankItem.fromJson(e as Map<String, dynamic>)).toList();
}
