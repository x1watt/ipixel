import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

/// Microphone analysis: RMS level (0..1) and an 11-band spectrum (0..1 each),
/// the same shape the panel firmware and the fx VU meter expect.
///
/// Linux needs `parecord` (pulseaudio-utils; works with PipeWire's pulse layer).
class MicAnalyzer {
  AudioRecorder? _rec; // created lazily so the plugin is only touched when used
  StreamSubscription? _sub;
  final _ctrl = StreamController<MicFrame>.broadcast();
  final _buf = <int>[];
  double _agc = 1000;
  static const sampleRate = 16000, fftN = 256, bands = 11;

  Stream<MicFrame> get frames => _ctrl.stream;
  bool get running => _sub != null;

  Future<void> start() async {
    final rec = _rec ??= AudioRecorder();
    if (!await rec.hasPermission()) throw StateError('microphone permission denied');
    final s = await rec.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits, sampleRate: sampleRate, numChannels: 1, autoGain: false, echoCancel: false));
    _sub = s.listen(_onPcm);
  }

  void _onPcm(Uint8List pcm) {
    final bd = ByteData.sublistView(pcm);
    for (var i = 0; i + 1 < pcm.length; i += 2) {
      _buf.add(bd.getInt16(i, Endian.little));
    }
    while (_buf.length >= fftN) {
      final chunk = _buf.sublist(0, fftN);
      _buf.removeRange(0, math.min(_buf.length, sampleRate ~/ 25)); // ~25 analyses/s
      _ctrl.add(_analyze(chunk));
    }
  }

  MicFrame _analyze(List<int> x) {
    var sum = 0.0;
    for (final v in x) {
      sum += v * v;
    }
    final rms = math.sqrt(sum / x.length);
    final db = 20 * math.log(rms / 32768 + 1e-9) / math.ln10; // -inf..0
    final level = ((db + 60) / 55).clamp(0.0, 1.0); // -60 dB .. -5 dB

    // Hann window + radix-2 FFT
    final re = Float64List(fftN), im = Float64List(fftN);
    for (var i = 0; i < fftN; i++) {
      re[i] = x[i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / (fftN - 1)));
    }
    _fft(re, im);
    final mags = Float64List(fftN ~/ 2);
    var peak = 0.0;
    for (var i = 1; i < fftN ~/ 2; i++) {
      mags[i] = math.sqrt(re[i] * re[i] + im[i] * im[i]);
      if (mags[i] > peak) peak = mags[i];
    }
    _agc = math.max(peak, _agc * 0.995); // slow-decay automatic gain
    // log-spaced bands between ~60 Hz and ~7 kHz
    final out = List<double>.filled(bands, 0);
    const lo = 1.0, hi = fftN / 2 - 1;
    for (var b = 0; b < bands; b++) {
      final f0 = (lo * math.pow(hi / lo, b / bands)).floor().clamp(1, fftN ~/ 2 - 1);
      final f1 = (lo * math.pow(hi / lo, (b + 1) / bands)).ceil().clamp(f0 + 1, fftN ~/ 2);
      var m = 0.0;
      for (var i = f0; i < f1; i++) {
        m = math.max(m, mags[i]);
      }
      out[b] = (m / (_agc + 1)).clamp(0.0, 1.0);
    }
    return MicFrame(level, out);
  }

  static void _fft(Float64List re, Float64List im) {
    final n = re.length;
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        final tr = re[i];
        re[i] = re[j];
        re[j] = tr;
        final ti = im[i];
        im[i] = im[j];
        im[j] = ti;
      }
    }
    for (var len = 2; len <= n; len <<= 1) {
      final ang = -2 * math.pi / len;
      final wr = math.cos(ang), wi = math.sin(ang);
      for (var i = 0; i < n; i += len) {
        var cr = 1.0, ci = 0.0;
        for (var k = 0; k < len ~/ 2; k++) {
          final a = i + k, b = i + k + len ~/ 2;
          final xr = re[b] * cr - im[b] * ci, xi = re[b] * ci + im[b] * cr;
          re[b] = re[a] - xr;
          im[b] = im[a] - xi;
          re[a] += xr;
          im[a] += xi;
          final ncr = cr * wr - ci * wi;
          ci = cr * wi + ci * wr;
          cr = ncr;
        }
      }
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _rec?.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
    await _ctrl.close();
    _rec?.dispose();
  }
}

class MicFrame {
  final double level;
  final List<double> bands;
  const MicFrame(this.level, this.bands);
}
