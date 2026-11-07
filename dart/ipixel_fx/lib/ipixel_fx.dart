/// Live effects engine for iPixel (and any small RGB) panels.
///
/// * [PanelCanvas]: RGB888 frame buffer with drawing primitives.
/// * [PixelFont]: crisp bitmap fonts (4x6, 5x7, 6x10, 6x13) + [Icons8].
/// * [Scene]: something that draws frames over time and may react to input.
/// * [LivePlayer]: streams a scene to an [IPixelDevice] as live frames.
/// * [sceneCatalog]: every built-in scene, grouped for a launcher UI.
library;

export 'src/canvas.dart';
export 'src/fonts.dart';
export 'src/icons.dart';
export 'src/scene.dart';
export 'src/player.dart';
export 'src/catalog.dart';
export 'src/scenes/effects.dart';
export 'src/scenes/clocks.dart';
export 'src/scenes/widgets.dart';
export 'src/scenes/games.dart';
export 'src/scenes/signs.dart';
