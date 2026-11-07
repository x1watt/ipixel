/// iPixel Color BLE LED display protocol.
///
/// Layers:
///  * [IPixelCommands] / [buildDataPackets] – pure byte builders (no I/O).
///  * [BleLink] – the tiny transport interface you implement per BLE stack.
///  * [IPixelDevice] – request/ack logic on top of a [BleLink].
library;

export 'src/constants.dart';
export 'src/codec.dart';
export 'src/commands.dart';
export 'src/advert.dart';
export 'src/panel.dart';
export 'src/text.dart';
export 'src/images.dart';
export 'src/ble_link.dart';
export 'src/device.dart';
