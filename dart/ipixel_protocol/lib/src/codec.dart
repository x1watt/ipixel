import 'dart:typed_data';

/// Builds a simple packet: `[u16 LE total length][u16 LE cmd][payload]`.
Uint8List frame(int cmd, [List<int> payload = const []]) {
  final len = 4 + payload.length;
  return Uint8List.fromList(
      [len & 0xFF, len >> 8 & 0xFF, cmd & 0xFF, cmd >> 8 & 0xFF, ...payload]);
}

List<int> u16le(int v) => [v & 0xFF, v >> 8 & 0xFF];
List<int> u32le(int v) => [v & 0xFF, v >> 8 & 0xFF, v >> 16 & 0xFF, v >> 24 & 0xFF];

int readU16le(List<int> b, int o) => b[o] | b[o + 1] << 8;

/// Standard CRC-32 (zlib / java.util.zip.CRC32, poly 0xEDB88320).
int crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc ^= b;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Splits a large payload into the per-frame packets the device expects.
///
/// Each packet: `[u16 len][u16 cmd][option: 0 first / 2 continuation][u32 total]`
/// followed, when [withCrc] is true, by `[u32 crc32(total payload)][flag][slot]`,
/// then the chunk. The device acks every packet (see [AckStatus]).
List<Uint8List> buildDataPackets({
  required int cmd,
  required List<int> data,
  required int frameSize,
  required bool withCrc,
  int flag = 0,
  int slot = 0,
}) {
  final crc = withCrc ? crc32(data) : 0;
  final out = <Uint8List>[];
  for (var off = 0, n = 0; off < data.length; off += frameSize, n++) {
    final end = off + frameSize < data.length ? off + frameSize : data.length;
    final chunk = data.sublist(off, end);
    final header = <int>[
      ...u16le(cmd),
      n == 0 ? 0 : 2,
      ...u32le(data.length),
      if (withCrc) ...[...u32le(crc), flag, slot],
    ];
    out.add(Uint8List.fromList([...u16le(2 + header.length + chunk.length), ...header, ...chunk]));
  }
  return out;
}

/// A device notification, decoded.
class Reply {
  final Uint8List bytes;
  Reply(this.bytes);

  int get length => bytes.length;
  int? get cmd => bytes.length >= 4 ? readU16le(bytes, 2) : null;

  /// Status byte for 5-byte acks, null otherwise.
  int? get status => bytes.length == 5 ? bytes[4] : null;
  bool get isAck => bytes.length == 5;

  @override
  String toString() => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
}
