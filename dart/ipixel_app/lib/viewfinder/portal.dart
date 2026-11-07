import 'dart:async';
import 'dart:math';

import 'package:dbus/dbus.dart';

/// Minimal xdg-desktop-portal ScreenCast client (GNOME/KDE Wayland).
///
/// The system share dialog appears every time a session starts; nothing is persisted
/// (persist_mode 0) and the cursor is not included (cursor_mode 1).
class PortalScreenCast {
  final DBusClient _bus;
  final DBusObjectPath _session;
  final int nodeId;
  final (int, int)? size;
  PortalScreenCast._(this._bus, this._session, this.nodeId, this.size);

  static const _dest = 'org.freedesktop.portal.Desktop';
  static const _iface = 'org.freedesktop.portal.ScreenCast';

  static Future<PortalScreenCast> open() async {
    final bus = DBusClient.session();
    final portal = DBusRemoteObject(bus, name: _dest, path: DBusObjectPath('/org/freedesktop/portal/desktop'));
    await bus.callMethod(
        destination: 'org.freedesktop.DBus', path: DBusObjectPath('/org/freedesktop/DBus'),
        interface: 'org.freedesktop.DBus', name: 'GetId', replySignature: DBusSignature('s'));
    final sender = bus.uniqueName.substring(1).replaceAll('.', '_');
    final rnd = Random();

    Future<Map<String, DBusValue>> call(String method, List<DBusValue> args, Map<String, DBusValue> opts) async {
      final token = 'ipixel${rnd.nextInt(1 << 30)}'; // one-off request id required by the portal API
      final path = DBusObjectPath('/org/freedesktop/portal/desktop/request/$sender/$token');
      final response = DBusSignalStream(bus, interface: 'org.freedesktop.portal.Request', name: 'Response', path: path).first;
      await Future.delayed(const Duration(milliseconds: 50));
      await portal.callMethod(_iface, method, [...args, DBusDict.stringVariant({...opts, 'handle_token': DBusString(token)})],
          replySignature: DBusSignature('o'));
      final sig = await response.timeout(const Duration(minutes: 2));
      if (sig.values[0].asUint32() != 0) throw StateError('screen sharing was cancelled');
      return sig.values[1].asStringVariantDict();
    }

    final created = await call('CreateSession', [], {'session_handle_token': DBusString('ipixels${rnd.nextInt(1 << 30)}')});
    final session = DBusObjectPath(created['session_handle']!.asString());
    await call('SelectSources', [session], {
      'types': DBusUint32(1), // monitors only
      'multiple': const DBusBoolean(false),
      'cursor_mode': DBusUint32(1), // hidden
      'persist_mode': DBusUint32(0), // never remember
    });
    final started = await call('Start', [session, const DBusString('')], {});
    final first = started['streams']!.asArray().first.asStruct();
    final props = first[1].asStringVariantDict();
    final s = props['size']?.asStruct();
    return PortalScreenCast._(bus, session, first[0].asUint32(), s == null ? null : (s[0].asInt32(), s[1].asInt32()));
  }

  Future<void> close() async {
    try {
      await _bus.callMethod(destination: _dest, path: _session, interface: 'org.freedesktop.portal.Session', name: 'Close');
    } catch (_) {}
    await _bus.close();
  }
}
