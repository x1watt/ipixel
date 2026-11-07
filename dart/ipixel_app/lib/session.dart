import 'package:ipixel_fx/ipixel_fx.dart';
import 'package:ipixel_protocol/ipixel_protocol.dart';

import 'mic.dart';
import 'programs_store.dart';

/// Everything the feature pages share for one connected panel.
class Session {
  final IPixelDevice device;
  final String name;
  final ProgramsStore store;
  late final LivePlayer player;
  final MicAnalyzer mic = MicAnalyzer();

  /// Listeners notified with every frame the player renders (for previews).
  final List<void Function(PanelCanvas)> frameListeners = [];
  double fps = 0;

  Session(this.device, this.name) : store = ProgramsStore('${device.panel!.code}') {
    player = LivePlayer(device, onFrame: (c) {
      for (final l in frameListeners) {
        l(c);
      }
    }, onFps: (f) => fps = f);
  }

  PanelInfo get panel => device.panel!;

  /// Stop anything streaming (scene player, mic) before an upload or mode change.
  Future<void> stopLive() async {
    await player.stop();
    await mic.stop();
  }

  Future<void> dispose() async {
    await stopLive();
    await mic.dispose();
    await device.close();
  }
}
