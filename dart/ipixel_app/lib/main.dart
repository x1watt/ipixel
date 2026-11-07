import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:ipixel_protocol/ipixel_protocol.dart';

import 'background.dart';
import 'pages/draw_page.dart';
import 'pages/fun_page.dart';
import 'pages/media_page.dart';
import 'pages/music_page.dart';
import 'pages/programs_page.dart';
import 'pages/text_page.dart';
import 'pages/tools_page.dart';
import 'pages/viewfinder_page.dart';
import 'session.dart';
import 'transport.dart';

void main() => runApp(const IPixelApp());

class IPixelApp extends StatelessWidget {
  const IPixelApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'iPixel Open',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark, useMaterial3: true),
        home: const ConnectPage(),
      );
}

// ---------------------------------------------------------------- connect

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});
  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  final _finder = DisplayFinder();
  List<FoundDisplay> _results = [];
  StreamSubscription? _scanSub, _stateSub;
  bool? _on;
  String? _connecting, _error;

  @override
  void initState() {
    super.initState();
    _stateSub = _finder.adapterOn.listen((on) {
      setState(() => _on = on);
      if (on == true) _scan();
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _stateSub?.cancel();
    _finder.dispose();
    super.dispose();
  }

  void _scan() {
    _scanSub?.cancel();
    setState(() => _error = null);
    _scanSub = _finder.scan().listen((r) => setState(() => _results = r), onError: (e) => setState(() => _error = '$e'));
  }

  Future<void> _open(FoundDisplay r) async {
    setState(() => _connecting = r.id);
    Session? session;
    try {
      final link = await _finder.connect(r);
      final dev = IPixelDevice(link, log: debugPrint);
      await dev.handshake(cid: r.advert?.cid, pid: r.advert?.pid);
      session = Session(dev, r.name);
      await session.store.load();
      await BackgroundMode.apply();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeviceHome(session: session!)));
    } catch (e) {
      setState(() => _error = 'Connection failed: $e');
    } finally {
      await BackgroundMode.stop();
      try {
        await session?.dispose();
      } catch (_) {}
      if (mounted) setState(() => _connecting = null);
      _scan();
    }
  }

  @override
  Widget build(BuildContext context) {
    final off = _on == false;
    return Scaffold(
      appBar: AppBar(title: const Text('iPixel displays'), actions: [
        IconButton(tooltip: 'Rescan', onPressed: off ? null : _scan, icon: const Icon(Icons.refresh)),
      ]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: off
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.bluetooth_disabled, size: 48),
                  const SizedBox(height: 8),
                  const Text('Bluetooth is off'),
                  if (Platform.isAndroid) TextButton(onPressed: _finder.turnOn, child: const Text('Turn on')),
                ])
              : ListView(padding: const EdgeInsets.all(12), children: [
                  if (_error != null)
                    Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!))),
                  if (_results.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Scanning for LED_BLE_… displays')]),
                    ),
                  for (final r in _results)
                    Card(
                      key: ValueKey(r.id),
                      child: ListTile(
                        leading: const Icon(Icons.grid_on),
                        title: Text(r.name),
                        subtitle: Text('${r.id} · RSSI ${r.rssi}'),
                        trailing: _connecting == r.id
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.chevron_right),
                        onTap: _connecting == null ? () => _open(r) : null,
                      ),
                    ),
                ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- device home

class _Feature {
  final IconData icon;
  final String title, blurb;
  final Widget Function(bool active) build;
  const _Feature(this.icon, this.title, this.blurb, this.build);
}

class DeviceHome extends StatefulWidget {
  final Session session;
  const DeviceHome({super.key, required this.session});
  @override
  State<DeviceHome> createState() => _DeviceHomeState();
}

class _DeviceHomeState extends State<DeviceHome> {
  int? _tab; // null = home grid (narrow layouts)
  late final List<_Feature> _features;
  bool _bg = true;

  late final _exit = AppLifecycleListener(onExitRequested: () async {
    try {
      await widget.session.dispose();
    } catch (_) {}
    return ui.AppExitResponse.exit;
  });

  @override
  void initState() {
    super.initState();
    _exit;
    BackgroundMode.enabled.then((v) => mounted ? setState(() => _bg = v) : null);
    final s = widget.session;
    _features = [
      _Feature(Icons.auto_awesome, 'Fun', 'Clocks, effects, signs, widgets, games', (a) => FunPage(session: s, active: a)),
      _Feature(Icons.text_fields, 'Text', 'Scrolling text the panel keeps playing', (_) => TextPage(session: s)),
      _Feature(Icons.image_outlined, 'Image / GIF', 'Pictures and animations', (_) => MediaPage(session: s)),
      _Feature(Icons.brush, 'Draw', 'Pixel art, live on the panel', (a) => DrawPage(session: s, active: a)),
      _Feature(Icons.graphic_eq, 'Music', 'Microphone visualizer', (a) => MusicPage(session: s, active: a)),
      if (Platform.isLinux)
        _Feature(Icons.crop_free, 'Viewfinder', 'Mirror part of the screen 1:1', (a) => ViewfinderPage(device: s.device, active: a, session: s)),
      _Feature(Icons.playlist_play, 'Programs', 'What is stored on the panel', (_) => ProgramsPage(session: s)),
      _Feature(Icons.tune, 'Tools', 'Clock faces, timers, schedules, settings', (_) => ToolsPage(session: s)),
    ];
  }

  @override
  void dispose() {
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.session.panel;
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final tab = _tab ?? (wide ? 0 : null);
    final seeThrough = tab != null && _features[tab].title == 'Viewfinder';
    final title = '${widget.session.name} · ${p.width}×${p.height}${tab != null && !wide ? ' · ${_features[tab].title}' : ''}';
    final body = tab == null
        ? _homeGrid(context)
        : IndexedStack(index: tab, children: [for (var i = 0; i < _features.length; i++) _features[i].build(i == tab)]);
    return PopScope(
      canPop: tab == null || wide,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tab = null);
      },
      child: Scaffold(
        backgroundColor: seeThrough ? Colors.transparent : null,
        appBar: AppBar(
          title: Text(title, overflow: TextOverflow.ellipsis),
          leading: tab != null && !wide ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _tab = null)) : null,
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'disconnect') {
                  Navigator.of(context).pop();
                  return;
                }
                if (v == 'bg') {
                  final next = !_bg;
                  setState(() => _bg = next);
                  BackgroundMode.setEnabled(next);
                }
              },
              itemBuilder: (_) => [
                if (Platform.isAndroid) CheckedPopupMenuItem(value: 'bg', checked: _bg, child: const Text('Keep running in background')),
                const PopupMenuItem(value: 'disconnect', child: Text('Disconnect')),
              ],
            ),
          ],
        ),
        body: wide
            ? Row(children: [
                NavigationRail(
                  selectedIndex: tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: [for (final f in _features) NavigationRailDestination(icon: Icon(f.icon), label: Text(f.title))],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ])
            : body,
      ),
    );
  }

  Widget _homeGrid(BuildContext context) => GridView.count(
        padding: const EdgeInsets.all(12),
        crossAxisCount: MediaQuery.sizeOf(context).width > 480 ? 3 : 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.15,
        children: [
          for (var i = 0; i < _features.length; i++)
            Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => setState(() => _tab = i),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(_features[i].icon, size: 32, color: Theme.of(context).colorScheme.primary),
                    const Spacer(),
                    Text(_features[i].title, style: Theme.of(context).textTheme.titleMedium),
                    Text(_features[i].blurb, style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ),
            ),
        ],
      );
}
