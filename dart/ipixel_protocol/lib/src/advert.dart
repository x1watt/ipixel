import 'constants.dart';

/// Info decoded from the advertisement (manufacturer data, company id 0x5452 "TR").
///
/// Payload after the 2-byte company id: `[0x00][0x72 'r'][cid hi][cid lo][pid][around][size]`.
/// CID/PID are built the way the app does it: decimal digits concatenated and left-padded.
class IPixelAdvert {
  final String? cid;
  final String? pid;
  final int? around;
  final int? size; // equals the handshake panel code on tested hardware
  const IPixelAdvert({this.cid, this.pid, this.around, this.size});

  /// [mfr] = manufacturer data *without* the company id (as flutter_blue_plus / bleak give it).
  static IPixelAdvert? fromManufacturerData(List<int> mfr) {
    if (mfr.length < 2 || mfr[1] != 0x72) return null;
    String? cid, pid;
    if (mfr.length > 4) {
      final c = '0000${mfr[2]}${mfr[3]}';
      cid = c.substring(c.length - 4);
      final p = mfr[4] >= 100 ? '000${mfr[4]}' : '00${mfr[4]}';
      pid = p.substring(p.length - (mfr[4] >= 100 ? 3 : 2));
    }
    return IPixelAdvert(
      cid: cid,
      pid: pid,
      around: mfr.length > 5 ? mfr[5] : null,
      size: mfr.length > 6 ? mfr[6] : null,
    );
  }

  /// True if a scan result looks like an iPixel display.
  static bool matches({String? name, Map<int, List<int>>? manufacturerData}) {
    if (name != null && name.contains(ipixelNamePrefix)) return true;
    final m = manufacturerData?[ipixelManufacturerIdLE];
    return m != null && m.length > 1 && m[1] == 0x72;
  }

  @override
  String toString() => 'IPixelAdvert(cid: $cid, pid: $pid, around: $around, size: $size)';
}
