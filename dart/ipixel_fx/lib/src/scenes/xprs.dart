import '../canvas.dart';
import '../fonts.dart';
import '../scene.dart';
import '../xprs.dart';

/// Displays XPRS messages on a small panel: a header line (who → whom, colour-
/// coded by packet type) and the message scrolling below it.
///
/// It holds a queue so a feed of packets rotates: each message scrolls once,
/// then the next takes over. The bridge that hears XPRS BLE just calls
/// [push] (or `setParam('packet', '<raw packet>')`); this scene is the display
/// half and needs no network of its own.
class XprsMessageScene extends SimpleScene {
  final List<XprsPacket> _queue = [];
  int _idx = 0;
  late Marquee _body;
  late PixelFont _bodyFont;
  late int _headerY, _bodyY;
  double _lastOffset = 0;
  bool _twoLine = true;
  bool _inited = false;
  double speed;

  XprsMessageScene({List<XprsPacket>? packets, this.speed = 18}) : super(color: 0xFFFFFF) {
    if (packets != null) _queue.addAll(packets);
  }

  @override
  String get name => 'XPRS messages';
  @override
  double get fps => 15;

  @override
  void init(int width, int height) {
    // Two lines when there's room for a tiny header (6px) plus a readable body.
    _twoLine = height >= 13;
    _headerY = 0;
    _bodyY = _twoLine ? PixelFont.tiny.h + 1 : (height - PixelFont.fitting(height).h) ~/ 2;
    _bodyFont = _twoLine ? PixelFont.fitting(height - PixelFont.tiny.h - 1) : PixelFont.fitting(height);
    _body = Marquee('', font: _bodyFont, pxPerSec: speed, gap: 12);
    _inited = true;
  }

  void _rebuildBody() {
    final old = _body;
    _body = Marquee(old.text, font: _bodyFont, pxPerSec: speed, gap: 12)..offset = old.offset;
  }

  @override
  void setParam(String key, Object value) {
    super.setParam(key, value);
    if (key == 'packet' && value is String) push(XprsPacket.parse(value));
    if (key == 'speed' && value is num) {
      speed = value.toDouble();
      if (_inited) _rebuildBody();
    }
    if (key == 'clear') {
      _queue.clear();
      _idx = 0;
    }
  }

  /// Add a packet to the rotation.
  void push(XprsPacket p) => _queue.add(p);

  @override
  bool onInput(SceneInput input) {
    if (_queue.length < 2) return false;
    if (input == SceneInput.right || input == SceneInput.action) {
      _advance();
      return true;
    }
    if (input == SceneInput.left) {
      _idx = (_idx - 1) % _queue.length;
      _resetBody();
      return true;
    }
    return false;
  }

  void _advance() {
    _idx = (_idx + 1) % _queue.length;
    _resetBody();
  }

  void _resetBody() {
    _body.offset = 0;
    _lastOffset = 0;
  }

  @override
  void draw(PanelCanvas c, double t, double dt) {
    c.clear(0);
    if (_queue.isEmpty) {
      PixelFont.small.drawCentered(c, 'XPRS', 0x2a4a66);
      return;
    }
    final p = _queue[_idx % _queue.length];
    final accent = _accent(p);

    if (_twoLine) {
      // Header: FROM>TO (or FROM for a broadcast), with a type tag for non-messages.
      final hdr = _header(p);
      PixelFont.tiny.draw(c, hdr, 0, _headerY, accent);
      // thin divider in the accent colour
      c.fillRect(0, PixelFont.tiny.h, c.width, 1, dim(accent, 0.3));
    }

    // Body: the message, scrolling. For non-message packets with no m:, show a summary.
    final text = _bodyText(p);
    _body.text = text;
    final bodyColor = p.cw.contains('adult') ? 0xff4060 : color;
    _body.draw(c, _bodyY, bodyColor, dt);

    // When the message has scrolled past once, rotate to the next packet.
    if (_queue.length > 1) {
      if (_body.offset < _lastOffset) _advance();
      _lastOffset = _body.offset;
    }
  }

  String _header(XprsPacket p) {
    final from = p.from ?? '?';
    final h = p.isBroadcast ? from : '$from>${p.to}';
    final t = p.type;
    if (t != null && t != 'message') {
      final tag = t.length > 4 ? t.substring(0, 4).toUpperCase() : t.toUpperCase();
      return '$tag $h';
    }
    return h;
  }

  String _bodyText(XprsPacket p) {
    if (p.message != null && p.message!.isNotEmpty) {
      final warn = p.cw.isNotEmpty ? '[${p.cw.join(',')}] ' : '';
      return '$warn${p.message}';
    }
    // No message body: summarise the machine packet so the panel still shows something.
    switch (p.type) {
      case 'receipt':
        return '${p.from ?? '?'} ${p.fields['s'] ?? 'ack'}';
      case 'observation':
        return '${p.from ?? '?'} heard ${p.fields['peers'] ?? '?'} peers';
      case 'command':
        return '${p.from ?? '?'} cmd:${p.fields['cmd'] ?? '?'}';
      default:
        return p.fields['title'] ?? p.type ?? '…';
    }
  }

  /// Colour the header by packet type / direction.
  int _accent(XprsPacket p) {
    if (p.cw.contains('adult')) return 0xff4060;
    switch (p.type) {
      case 'info':
      case 'offer':
        return 0xffa000; // amber: public notices
      case 'blog':
        return 0x40c0ff; // cyan: posts
      case 'receipt':
      case 'observation':
      case 'command':
        return 0x808080; // grey: machine traffic
    }
    return p.isBroadcast ? 0x40ff70 : 0xffffff; // green: to a group/all, white: direct
  }
}
