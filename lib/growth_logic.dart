import 'dart:math';

import 'models.dart';

class GrowthEngineConfig {
  final double baseMuMm;
  final double baseSigmaMm;
  final double baseMinMm;
  final double baseMaxMm;
  final int cleanlinessDecayPerDay; // d
  final double bonusOnWaterChangeMm; // +bonus same-day
  final double kBaseMin; // 0.5
  final double kBaseMax; // 1.0
  final double kBoostOnWater; // +0.1 for 3 days
  final double kBoostCap; // 1.2
  final int kBoostDays; // 3 days

  const GrowthEngineConfig({
    this.baseMuMm = 0.15,
    this.baseSigmaMm = 0.05,
    this.baseMinMm = 0.0,
    this.baseMaxMm = 0.3,
    this.cleanlinessDecayPerDay = 8,
    this.bonusOnWaterChangeMm = 0.1,
    this.kBaseMin = 0.5,
    this.kBaseMax = 1.0,
    this.kBoostOnWater = 0.1,
    this.kBoostCap = 1.2,
    this.kBoostDays = 3,
  });
}

class GrowthEngine {
  final GrowthEngineConfig config;
  final Random _rng;
  GrowthEngine({this.config = const GrowthEngineConfig(), Random? rng}) : _rng = rng ?? Random();

  // Normal distribution using Box-Muller
  double _randomNormal(double mu, double sigma) {
    final u1 = _rng.nextDouble().clamp(1e-12, 1.0);
    final u2 = _rng.nextDouble();
    final z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
    return mu + sigma * z0;
  }

  double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

  double _growthDeltaForDay(Marimo m, DateTime day) {
    // base delta
    final base = _clamp(
      _randomNormal(config.baseMuMm, config.baseSigmaMm),
      config.baseMinMm,
      config.baseMaxMm,
    );
    // cleanliness factor
    final cleanlinessFactor = config.kBaseMin + (config.kBaseMax - config.kBaseMin) * (m.cleanliness / 100.0);
    // water boost window
    final boostActive = (m.waterBoostUntil != null && !day.isAfter(m.waterBoostUntil!));
    final kBoost = boostActive ? config.kBoostOnWater : 0.0;
    final k = _clamp(cleanlinessFactor + kBoost, config.kBaseMin, config.kBoostCap);
    return base * k;
  }

  /// Applies growth ticks from `fromDateExclusive` (e.g., lastGrowthTickAt's day)
  /// up to but not including today if run at 00:00 boundary, or inclusive when called during day.
  /// Returns updated marimo, and logs for each day applied.
  (Marimo, List<GrowthLog>) applyDailyGrowth({
    required Marimo marimo,
    required DateTime now,
    required List<GrowthLog> existingLogs,
  }) {
    if (marimo.state == MarimoState.dead) {
      // No growth while dead
      return (marimo, existingLogs);
    }

    DateTime dayCursor = _asLocalYMD(marimo.lastGrowthTickAt);
    final today = _asLocalYMD(now);
    var m = marimo;
    final logs = List<GrowthLog>.from(existingLogs);

    while (dayCursor.isBefore(today)) {
      dayCursor = dayCursor.add(const Duration(days: 1));
      // Daily cleanliness decay
      final newClean = max(0, m.cleanliness - config.cleanlinessDecayPerDay);
      m = m.copyWith(cleanliness: newClean);

      // Growth for that day
      final delta = _growthDeltaForDay(m, dayCursor);
      final newSize = m.sizeMm + delta;
      m = m.copyWith(sizeMm: newSize, lastGrowthTickAt: dayCursor);

      logs.add(GrowthLog(
        date: dayCursor,
        deltaMm: delta,
        sizeAfterMm: newSize,
        cleanlinessAfter: newClean,
      ));
    }
    // Death check after progression
    final lastCare = m.lastWaterChangeAt.isAfter(m.lastInteractionAt) ? m.lastWaterChangeAt : m.lastInteractionAt;
    if (now.difference(lastCare).inDays >= 10) {
      m = m.copyWith(state: MarimoState.dead);
    }

    return (m, logs);
  }

  Marimo applyWaterChange({required Marimo marimo, required DateTime now}) {
    // cooldown 24h
    if (now.difference(marimo.lastWaterChangeAt).inHours < 24) {
      return marimo;
    }
    var m = marimo.copyWith(
      cleanliness: 100,
      lastWaterChangeAt: now,
      lastInteractionAt: now,
      waterBoostUntil: _asLocalYMD(now).add(Duration(days: config.kBoostDays)),
    );
    // Same-day bonus
    m = m.copyWith(sizeMm: m.sizeMm + config.bonusOnWaterChangeMm);
    return m;
  }

  DateTime _asLocalYMD(DateTime dt) {
    final local = dt.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}

