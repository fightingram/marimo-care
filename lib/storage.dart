import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class StorageKeys {
  static const marimo = 'marimo_data_v1';
  static const growthLogs = 'growth_logs_v1';
  static const settings = 'user_settings_v1';
  static const items = 'tank_items_v1';
  static const tutorialShown = 'tutorial_shown_v1';
}

class AppStorage {
  AppStorage._();
  static final AppStorage instance = AppStorage._();

  Future<Marimo?> loadMarimo() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageKeys.marimo);
    if (raw == null) return null;
    return Marimo.decode(raw);
  }

  Future<void> saveMarimo(Marimo m) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.marimo, Marimo.encode(m));
  }

  Future<List<GrowthLog>> loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageKeys.growthLogs);
    if (raw == null) return [];
    return GrowthLog.decodeList(raw);
  }

  Future<void> saveLogs(List<GrowthLog> logs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.growthLogs, GrowthLog.encodeList(logs));
  }

  Future<UserSetting> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageKeys.settings);
    if (raw == null) {
      return UserSetting(
        notificationsEnabled: true,
        screenshotWatermark: true,
        haptics: true,
        floatingEnabled: true,
        backgroundIndex: 0,
        customBackgroundPath: null,
        debugNowOverride: null,
      );
    }
    return UserSetting.decode(raw);
  }

  Future<void> saveSettings(UserSetting s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.settings, UserSetting.encode(s));
  }

  Future<List<TankItem>> loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(StorageKeys.items);
    if (raw == null) return [];
    try {
      return TankItem.decodeList(raw);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveItems(List<TankItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.items, TankItem.encodeList(items));
  }

  Future<bool> isTutorialShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(StorageKeys.tutorialShown) ?? false;
  }

  Future<void> setTutorialShown(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.tutorialShown, value);
  }
}
