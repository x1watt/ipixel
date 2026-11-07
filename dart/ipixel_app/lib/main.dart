import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:ipixel_protocol/ipixel_protocol.dart';

import 'pages/control_page.dart';
import 'pages/media_page.dart';
import 'pages/viewfinder_page.dart';
import 'pages/text_page.dart';
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
    _scanSub = _finder.scan().listen((r) => setState(() => _results = r),
        onError: (e) => setState(() => _error = '$e'));
  }

  Future<void> _open(FoundDisplay r) async {
    debugPrint('connect: ${r.id}');
    setState(() => _connecting = r.id);
    IPixelDevice? dev;
    try {
      final link = await _finder.connect(r);
      dev = IPixelDevice(link, log: debugPrint);
      await dev.handshake(cid: r.advert?.cid, pid: r.advert?.pid);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeviceHome(device: dev!, name: r.name)));
    } catch (e) {
      setState(() => _error = 'Connection failed: $e');
    } finally {
      try {
        await dev?.close();
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
                    Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!))),
                  if (_results.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Scanning for LED_BLE_… displays'),
                      ]),
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

class DeviceHome extends StatefulWidget {
  final IPixelDevice device;
  final String name;
  const DeviceHome({super.key, required this.device, required this.name});
  @override
  State<DeviceHome> createState() => _DeviceHomeState();
}

class _DeviceHomeState extends State<DeviceHome> {
  int _tab = 0;
  static const _viewfinderTab = 2;

  // Disconnect cleanly when the window is closed, otherwise BlueZ keeps a stale link
  // and the panel stops advertising until it times out.
  late final _exit = AppLifecycleListener(onExitRequested: () async {
    try {
      await widget.device.close();
    } catch (_) {}
    return ui.AppExitResponse.exit;
  });

  @override
  void initState() {
    super.initState();
    _exit; // register
  }

  @override
  void dispose() {
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.device.panel!;
    final pages = <(IconData, String, Widget)>[
      (Icons.text_fields, 'Text', TextPage(device: widget.device)),
      (Icons.image_outlined, 'Image / GIF', MediaPage(device: widget.device)),
      (Icons.crop_free, 'Viewfinder',
          ViewfinderPage(device: widget.device, active: _tab == _viewfinderTab)),
      (Icons.tune, 'Control', ControlPage(device: widget.device)),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final body = IndexedStack(index: _tab, children: [for (final pg in pages) pg.$3]);
    final seeThrough = _tab == _viewfinderTab;
    return Scaffold(
      // transparent only behind the viewfinder tab; its page paints its own opaque parts
      backgroundColor: seeThrough ? Colors.transparent : null,
      appBar: AppBar(title: Text('${widget.name} · ${p.width}×${p.height}')),
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final pg in pages) NavigationRailDestination(icon: Icon(pg.$1), label: Text(pg.$2)),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ])
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [for (final pg in pages) NavigationDestination(icon: Icon(pg.$1), label: pg.$2)],
            ),
    );
  }
}
