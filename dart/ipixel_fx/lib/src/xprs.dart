/// Parser for the XPRS packet wire format (see xprs spec §4).
///
/// A packet is space-separated `key:value` fields. `t:` is always first; `m:`,
/// when present, is always last and everything after it is the message — so it
/// may contain spaces, colons, URLs and punctuation with no escaping.
///
///   t:message f:X1QZ3N d:LISBOA ts:2026-08-08_14:26:40 m:net starts in ten minutes
///
/// Unknown keys are kept verbatim; a display reads the few it cares about.
library;

class XprsPacket {
  /// All header fields (everything except the message body).
  final Map<String, String> fields;

  /// The `m:` body, or null when the packet carries no message.
  final String? message;

  const XprsPacket(this.fields, this.message);

  String? get type => fields['t'];
  String? get from => fields['f'];
  String? get to => fields['d'];
  String? get timestamp => fields['ts'];
  String? get lang => fields['lang'];

  /// Content warnings (`cw:adult,flashing` → ['adult','flashing']).
  List<String> get cw => _csv('cw');
  List<String> get tags => _csv('tag');
  List<String> _csv(String k) =>
      (fields[k] ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  /// No `d:` means a broadcast (shown as "all").
  bool get isBroadcast => to == null || to!.isEmpty;

  /// Parse one packet line. Tolerant: a malformed token is skipped.
  static XprsPacket parse(String raw) {
    final s = raw.trim();
    final m = RegExp(r'(^|\s)m:').firstMatch(s);
    final header = m == null ? s : s.substring(0, m.start);
    final message = m == null ? null : s.substring(m.end);
    final fields = <String, String>{};
    for (final tok in header.split(RegExp(r'\s+'))) {
      if (tok.isEmpty) continue;
      final ci = tok.indexOf(':');
      if (ci <= 0) continue; // no key, or empty key
      fields[tok.substring(0, ci)] = tok.substring(ci + 1);
    }
    return XprsPacket(fields, message);
  }

  @override
  String toString() => 'XprsPacket($fields, m:$message)';
}
