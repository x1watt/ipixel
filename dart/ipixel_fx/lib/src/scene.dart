import 'canvas.dart';

/// Input events a scene may react to (keyboard, buttons, touch swipes, mic level).
enum SceneInput { up, down, left, right, action, back }

/// Something that draws itself onto a [PanelCanvas] over time.
abstract class Scene {
  /// Human-readable name for the launcher.
  String get name;

  /// Preferred frame rate. The player drops to what the link can carry.
  double get fps => 8;

  /// Called once with the panel size before the first frame.
  void init(int width, int height) {}

  /// Draw the next frame. [t] seconds since start, [dt] since the previous frame.
  void draw(PanelCanvas c, double t, double dt);

  /// Optional input (games, menus). Return true if consumed.
  bool onInput(SceneInput input) => false;

  /// Optional live data (mic level 0..1, text updates, …).
  void setParam(String key, Object value) {}
}

/// Small tweakable knob shown by the launcher UI.
class SceneParam {
  final String key, label;
  final double min, max, value;
  const SceneParam(this.key, this.label, this.min, this.max, this.value);
}

/// Scene with a colour and declared params; most built-ins extend this.
abstract class SimpleScene extends Scene {
  int color;
  SimpleScene({this.color = 0xFFFFFF});
  List<SceneParam> get params => const [];

  @override
  void setParam(String key, Object value) {
    if (key == 'color' && value is int) color = value;
  }
}
