import 'dart:io';

import 'package:flutter_background/flutter_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the app (and its BLE link + running scene) alive on Android when it is not in
/// the foreground, through a foreground service with a persistent notification.
/// Optional, on by default.
class BackgroundMode {
  static const _key = 'background_enabled';

  static Future<bool> get enabled async => (await SharedPreferences.getInstance()).getBool(_key) ?? true;

  static Future<void> setEnabled(bool v) async {
    await (await SharedPreferences.getInstance()).setBool(_key, v);
    if (v) {
      await apply();
    } else {
      await stop();
    }
  }

  /// Call once a panel is connected. No-op outside Android or when disabled.
  static Future<bool> apply() async {
    if (!Platform.isAndroid || !await enabled) return false;
    try {
      final ok = await FlutterBackground.initialize(
          androidConfig: const FlutterBackgroundAndroidConfig(
        notificationTitle: 'iPixel Open',
        notificationText: 'Connected to your LED panel',
        notificationImportance: AndroidNotificationImportance.normal,
        notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
      ));
      if (!ok) return false;
      return await FlutterBackground.enableBackgroundExecution();
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      if (FlutterBackground.isBackgroundExecutionEnabled) await FlutterBackground.disableBackgroundExecution();
    } catch (_) {}
  }
}
