/// JieLi RCSP device authentication (Bluetooth legacy E1 / SAFER+).
///
/// The OTA service (0xAE00) stays silent until the host completes this handshake.
/// Ported from the public francozappa/bias SAFER+ implementation (MIT) and matched
/// against its test vectors; the fixed key/address are the constants compiled into
/// the iPixel app's `libjl_ota_auth.so` (same values Quarkslab recovered for JieLi).
///
/// Handshake on AE01(write)/AE02(notify), 17-byte frames:
///   host -> 00 <16 rand>         ; device -> 01 <16 = e1(rand)>
///   host -> 02 "pass"            ; device -> 00 <16 chal>
///   host -> 01 <16 = e1(chal)>   ; device -> 02 "pass"  (authenticated)
library;

/// The fixed 16-byte E1 key from libjl_ota_auth.so (.rodata @0x3150).
const jlAuthKey = [0x06, 0x77, 0x5f, 0x87, 0x91, 0x8d, 0xd4, 0x23, 0x00, 0x5d, 0xf1, 0xd8, 0xcf, 0x0c, 0x14, 0x2b];

/// The fixed 6-byte address the library feeds E1 (.rodata @0x3160).
const jlAuthAddr = [0x11, 0x22, 0x33, 0x33, 0x22, 0x11];

/// The success marker: 0x02 "pass".
const jlAuthPass = [0x02, 0x70, 0x61, 0x73, 0x73];

int _modpow(int b, int e, int m) {
  var r = 1;
  b %= m;
  while (e > 0) {
    if (e & 1 == 1) r = r * b % m;
    e >>= 1;
    b = b * b % m;
  }
  return r;
}

final List<int> _exp = List<int>.generate(256, (i) => _modpow(45, i, 257) % 256);
final List<int> _log = () {
  final l = List<int>.filled(256, 0);
  for (var i = 0; i < 256; i++) {
    l[_exp[i]] = i;
  }
  return l;
}();

const _p1 = {0, 3, 4, 7, 8, 11, 12, 15};
const _perm = [8, 11, 12, 15, 2, 1, 6, 5, 10, 9, 14, 13, 0, 7, 4, 3];
const _bHex = {
  2: '4697b1baa3b7100ac537b3c95a28ac64', 3: 'ecabaac66795580df89af66e66dc053d',
  4: '8ac3d8896ae9364943bfebd4969b68a0', 5: '5d57921fd5715cbb22c1be7bbc996394',
  6: '2a61b8343219fdfb1740e6511d41448f', 7: 'dd0480dee731d67f01a2f739da6f23ca',
  8: '3ad01cd1303e12a1cd0fe0a8af82592c', 9: '7dadb2efc287ce75061302904f2e7233',
  10: 'c08dcfa981e2c4272f6c7a9f52e11538', 11: 'fc2042c708e409555e8c147660ffdfd7',
  12: 'fa0b21001af9a6b9e89e624cd99150d2', 13: '18b40784ea5ba4c80ecb48694b4e9c35',
  14: '454d54e5253c0c4a8b3fcca7db6baef4', 15: '2df37c6d9db52674f29353b0f011ed83',
  16: 'b60316733b1e8e70bd861b477e2456f1', 17: '884697b1baa3b7100ac537b3c95a28ac',
};
List<int> _hx(String s) => [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];
final Map<int, List<int>> _b = _bHex.map((k, v) => MapEntry(k, _hx(v)));

List<int> _addOne(List<int> a, List<int> b) => [for (var i = 0; i < 16; i++) _p1.contains(i) ? a[i] ^ b[i] : (a[i] + b[i]) & 255];
List<int> _addTwo(List<int> a, List<int> b) => [for (var i = 0; i < 16; i++) _p1.contains(i) ? (a[i] + b[i]) & 255 : a[i] ^ b[i]];
List<int> _nonlin(List<int> t) => [for (var i = 0; i < 16; i++) _p1.contains(i) ? _exp[t[i]] : _log[t[i]]];
List<int> _pht(List<int> t) {
  final o = [...t];
  for (var i = 0; i < 8; i++) {
    final x = o[2 * i], y = o[2 * i + 1];
    o[2 * i] = (2 * x + y) & 255;
    o[2 * i + 1] = (x + y) & 255;
  }
  return o;
}
List<int> _permf(List<int> t) => [for (var k = 0; k < 16; k++) t[_perm[k]]];
List<int> _rotl3(List<int> a) => [for (final b in a) ((b << 3) | (b >> 5)) & 255];

Map<int, List<int>> _keySched(List<int> k) {
  var x = 0;
  for (final b in k) {
    x ^= b;
  }
  var presel = [...k, x]; // 17 bytes
  final keys = <int, List<int>>{1: [...k]};
  for (var n = 2; n <= 17; n++) {
    presel = _rotl3(presel);
    final pre = [for (var j = 0; j < 16; j++) presel[(n - 1 + j) % 17]];
    keys[n] = [for (var j = 0; j < 16; j++) (pre[j] + _b[n]![j]) & 255];
  }
  return keys;
}

List<int> _ar(Map<int, List<int>> keys, List<int> xIn, bool isPrime) {
  var t = [...xIn];
  var ar9 = t;
  for (var r = 1; r <= 8; r++) {
    if (isPrime && r == 3) t = _addOne(t, xIn);
    t = _addOne(t, keys[2 * r - 1]!);
    t = _nonlin(t);
    t = _addTwo(t, keys[2 * r]!);
    t = _pht(t);
    t = _permf(t);
    t = _pht(t);
    t = _permf(t);
    t = _pht(t);
    t = _permf(t);
    t = _pht(t);
    ar9 = t;
  }
  return _addOne(ar9, keys[17]!);
}

// K~ : per-byte additive(+)/xor(^) constants for the Ar' key.
const _ktOp = [1, 0, 1, 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0, 1]; // 1=add, 0=xor
const _ktC = [233, 229, 223, 193, 179, 167, 149, 131, 233, 229, 223, 193, 179, 167, 149, 131];
List<int> _ktilde(List<int> k) => [for (var i = 0; i < 16; i++) _ktOp[i] == 1 ? (k[i] + _ktC[i]) & 255 : k[i] ^ _ktC[i]];

/// Bluetooth E1(key, rand, addr6) -> 16 bytes (SRES||ACO). `addr6` is 6 bytes.
List<int> e1(List<int> key, List<int> rand, List<int> addr6) {
  final keys = _keySched(key);
  final keysP = _keySched(_ktilde(key));
  final arOut = _ar(keys, rand, false);
  final e = [for (var i = 0; i < 16; i++) addr6[i % 6]];
  final xp = [for (var i = 0; i < 16; i++) (e[i] + (arOut[i] ^ rand[i])) & 255];
  return _ar(keysP, xp, true);
}

/// The device's expected response to our challenge (and our response to the device's).
List<int> jlAuthResponse(List<int> challenge16) => e1(jlAuthKey, challenge16, jlAuthAddr);

/// Self-check against the francozappa/bias vectors + our panel's recovered vector.
bool e1SelfTest() {
  List<int> h(String s) => _hx(s);
  String x(List<int> b) => b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  final vecs = [
    ['00000000000000000000000000000000', '00000000000000000000000000000000', '000000000000', '056c0fe648afcdd4bd40fef76693b113'],
    ['159dd9f43fc3d328efba0cd8a861fa57', 'bc3f30689647c8d7c5a03ca80a91eceb', '7ca89b233c2d', '8d5205c53ed75df4abd9af638d144e94'],
    ['45298d06e46bac21421ddfbed94c032b', '0891caee063f5da1809577ff94ccdcfb', 'c62f19f6ce98', '00507e5f2a5f19fbf60907e69f39ca9f'],
    ['35949a914225fabad91995d226de1d92', '0ecd61782b4128480c05dc45542b1b8c', 'f428f0e624b3', '80e5629ca6fe4dcde3924611d3cc6ba1'],
  ];
  for (final v in vecs) {
    if (x(e1(h(v[0]), h(v[1]), h(v[2]))) != v[3]) return false;
  }
  return x(jlAuthResponse(h('abb2cdc69bb454110e827441213ddc87'))) == '61721f97c869523ccce093d7f849ca02';
}
