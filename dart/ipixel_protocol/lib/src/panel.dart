import 'codec.dart';

/// Panel description derived from the handshake reply.
class PanelInfo {
  /// Raw code in handshake reply byte 4 (e.g. 0x83).
  final int code;

  /// The app's internal LED type index (AppConfig.ledType), or null if unknown.
  final int? ledType;
  final int width, height;

  /// Bytes per upload frame (AppConfig.ledFrameSize): 12288 for 64x64 / 32x32 boards, else 4096.
  final int frameSize;

  /// Device reports a password is set (reply byte 10 == 1): send verifyPassword first.
  final bool passwordEnabled;

  const PanelInfo(this.code, this.ledType, this.width, this.height, this.frameSize, this.passwordEnabled);

  int get rgbFrameBytes => width * height * 3;

  /// Decode a handshake reply (`0b 00 01 80 <code> …`). Pass [cid]/[pid] from the
  /// advertisement to resolve the few model-specific codes.
  static PanelInfo fromHandshake(List<int> reply, {String? cid, String? pid}) {
    if (reply.length < 5 || readU16le(reply, 2) != 0x8001) {
      throw ArgumentError('not a handshake reply: $reply');
    }
    final code = reply[4];
    var type = codeToLedType[code];
    if (code == 0x81 && cid == '0001' && pid == '55') type = 21;
    if (code == 0x82 && cid == '0001' && pid == '56') type = 22;
    if (code == 0x89 && cid == '0001' && pid == '57') type = 23;
    final size = type != null && type < ledTypeSizes.length ? ledTypeSizes[type] : (0, 0);
    final big = code == 0x00 || code == 0x80 || code == 0x81;
    return PanelInfo(code, type, size.$1, size.$2, big ? 12288 : 4096,
        reply.length > 10 && reply[10] == 1);
  }

  @override
  String toString() =>
      'PanelInfo(code: 0x${code.toRadixString(16)}, ledType: $ledType, ${width}x$height, frame: $frameSize, pwd: $passwordEnabled)';
}

/// Handshake code -> app ledType (ChooseActivity.setLedType).
const Map<int, int> codeToLedType = {
  0x00: 0, 0x80: 0, 0x81: 2, 0x82: 4, 0x83: 3, 0x84: 1, 0x85: 5, 0x86: 6, 0x87: 7, 0x88: 8,
  0x89: 9, 0x8A: 10, 0x8B: 11, 0x8C: 12, 0x8D: 13, 0x8E: 14, 0x8F: 15, 0x90: 16, 0x91: 17,
  0x92: 18, 0x93: 19, 0x94: 20, 0x95: 24, 0x96: 25, 0x97: 26, 0x98: 27, 0x99: 28, 0x9A: 29,
  0x9B: 30, 0x9C: 31, 0x9D: 32, 0x9E: 33, 0x9F: 34, 0xA0: 35,
};

/// app ledType -> (width, height) (AppConfig.ledSizeMap).
const List<(int, int)> ledTypeSizes = [
  (64, 64), (96, 16), (32, 32), (64, 16), (32, 16), (64, 20), (128, 32), (144, 16), (192, 16),
  (48, 24), (64, 32), (96, 32), (128, 32), (96, 32), (160, 32), (192, 32), (256, 32), (320, 32),
  (384, 32), (448, 32), (16, 16), (32, 32), (32, 16), (48, 24), (64, 64), (96, 64), (128, 64),
  (160, 64), (192, 64), (256, 64), (320, 64), (384, 64), (448, 64), (512, 64), (576, 64), (640, 64),
];
