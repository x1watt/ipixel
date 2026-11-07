import 'scene.dart';
import 'scenes/clocks.dart';
import 'scenes/effects.dart';
import 'scenes/games.dart';
import 'scenes/signs.dart';
import 'scenes/widgets.dart';

/// A launcher entry: a factory so every play starts fresh.
class SceneEntry {
  final String name, group;
  final Scene Function() create;

  /// Needs arrow keys / action button.
  final bool interactive;
  const SceneEntry(this.name, this.group, this.create, {this.interactive = false});
}

/// Every built-in scene, grouped for a launcher UI.
final List<SceneEntry> sceneCatalog = [
  SceneEntry('Digital clock', 'Clocks', () => DigitalClockScene()),
  SceneEntry('Clock + date', 'Clocks', () => DigitalClockScene(showDate: true, seconds: false)),
  SceneEntry('Analog clock', 'Clocks', () => AnalogClockScene()),
  SceneEntry('Binary clock', 'Clocks', () => BinaryClockScene()),
  SceneEntry('Pomodoro timer', 'Clocks', () => TimerScene(), interactive: true),
  SceneEntry('Stopwatch', 'Clocks', () => StopwatchScene(), interactive: true),
  SceneEntry('Countdown to date', 'Clocks', () => CountdownScene()),
  SceneEntry('Plasma', 'Effects', () => PlasmaScene()),
  SceneEntry('Fire', 'Effects', () => FireScene()),
  SceneEntry('Matrix', 'Effects', () => MatrixScene()),
  SceneEntry('Rainbow', 'Effects', () => RainbowScene()),
  SceneEntry('Starfield', 'Effects', () => StarfieldScene()),
  SceneEntry('Warp', 'Effects', () => WarpScene()),
  SceneEntry('Sparkle', 'Effects', () => SparkleScene()),
  SceneEntry('Bouncing balls', 'Effects', () => BallsScene()),
  SceneEntry('Game of Life', 'Effects', () => LifeScene()),
  SceneEntry('Lava lamp', 'Effects', () => LavaScene()),
  SceneEntry('Text effects', 'Text', () => TextFxScene()),
  SceneEntry('Ticker', 'Text', () => TickerScene()),
  SceneEntry('Icon parade', 'Text', () => IconParadeScene()),
  for (final s in SignScene.presets()) SceneEntry(s.text, 'Signs', () => SignScene(s.text, icon: s.icon, color: s.color, pulse: s.pulse)),
  SceneEntry('System monitor', 'Widgets', () => SystemStatsScene()),
  SceneEntry('Progress bar', 'Widgets', () => ProgressScene()),
  SceneEntry('Music meter', 'Widgets', () => VuMeterScene()),
  SceneEntry('Status icons', 'Widgets', () => StatusScene()),
  SceneEntry('Snake', 'Games', () => SnakeScene(), interactive: true),
  SceneEntry('Pong', 'Games', () => PongScene(), interactive: true),
  SceneEntry('Breakout', 'Games', () => BreakoutScene(), interactive: true),
  SceneEntry('Flappy', 'Games', () => FlappyScene(), interactive: true),
  SceneEntry('Tetris', 'Games', () => TetrisScene(), interactive: true),
];

List<String> get sceneGroups => sceneCatalog.map((e) => e.group).toSet().toList();
