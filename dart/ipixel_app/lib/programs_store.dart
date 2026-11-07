import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A program stored on the panel, as remembered by this app (the firmware has no
/// "list slots" command, so the official app keeps the same bookkeeping on the phone).
class Program {
  final int slot;
  final String name, kind; // kind: text | gif | draw
  final DateTime created;
  Program({required this.slot, required this.name, required this.kind, DateTime? created})
      : created = created ?? DateTime.now();

  Map<String, Object> toJson() => {'slot': slot, 'name': name, 'kind': kind, 'created': created.toIso8601String()};
  static Program fromJson(Map<String, dynamic> j) => Program(
      slot: j['slot'] as int, name: j['name'] as String, kind: j['kind'] as String,
      created: DateTime.tryParse(j['created'] as String? ?? ''));
}

/// Per-panel program list + playlist, persisted with shared_preferences.
class ProgramsStore {
  final String panelKey;
  final List<Program> programs = [];
  List<int> playlist = [];
  ProgramsStore(this.panelKey);

  String get _k => 'programs_$panelKey';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    programs
      ..clear()
      ..addAll([for (final e in jsonDecode(p.getString(_k) ?? '[]') as List) Program.fromJson(e as Map<String, dynamic>)]);
    playlist = [for (final e in jsonDecode(p.getString('${_k}_playlist') ?? '[]') as List) e as int];
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_k, jsonEncode([for (final e in programs) e.toJson()]));
    await p.setString('${_k}_playlist', jsonEncode(playlist));
  }

  /// Lowest free slot >= 1 (same rule as the official app).
  int nextSlot() {
    final used = programs.map((e) => e.slot).toSet();
    var s = 1;
    while (used.contains(s)) {
      s++;
    }
    return s;
  }

  Future<void> add(Program prog) async {
    programs.removeWhere((e) => e.slot == prog.slot);
    programs.add(prog);
    programs.sort((a, b) => a.slot.compareTo(b.slot));
    await save();
  }

  Future<void> remove(int slot) async {
    programs.removeWhere((e) => e.slot == slot);
    playlist.remove(slot);
    await save();
  }

  Future<void> clear() async {
    programs.clear();
    playlist.clear();
    await save();
  }
}
