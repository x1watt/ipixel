import 'package:flutter/material.dart';

import '../session.dart';
import 'common.dart';

/// Programs stored on the panel (text, GIFs, drawings) and the playlist the panel cycles.
class ProgramsPage extends StatefulWidget {
  final Session session;
  const ProgramsPage({super.key, required this.session});
  @override
  State<ProgramsPage> createState() => _ProgramsPageState();
}

class _ProgramsPageState extends State<ProgramsPage> with RunAction {
  Session get s => widget.session;

  @override
  Widget build(BuildContext context) {
    final store = s.store;
    return PageBody(children: [
      Row(children: [
        Expanded(child: Text('${store.programs.length} stored · playlist: ${store.playlist.isEmpty ? 'none' : store.playlist.join(', ')}',
            style: Theme.of(context).textTheme.titleSmall)),
        FilledButton.icon(
            onPressed: store.playlist.isEmpty ? null : () => run('Play list', () async {
                  await s.stopLive();
                  return s.device.playlist(store.playlist);
                }),
            icon: const Icon(Icons.playlist_play),
            label: const Text('Play list')),
      ]),
      const SizedBox(height: 8),
      if (store.programs.isEmpty)
        const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Nothing stored yet. Use "Store on panel" in Text, Image / GIF or Draw.', textAlign: TextAlign.center)),
      for (final p in store.programs)
        Card(
          child: ListTile(
            leading: CircleAvatar(child: Text('${p.slot}')),
            title: Text(p.name),
            subtitle: Text('${p.kind} · ${p.created.day}/${p.created.month}'),
            trailing: Wrap(children: [
              IconButton(tooltip: 'Show now', icon: const Icon(Icons.play_arrow), onPressed: () => run('Play ${p.slot}', () async {
                    await s.stopLive();
                    return s.device.playlist([p.slot]);
                  })),
              IconButton(
                  tooltip: store.playlist.contains(p.slot) ? 'Remove from playlist' : 'Add to playlist',
                  icon: Icon(store.playlist.contains(p.slot) ? Icons.playlist_remove : Icons.playlist_add),
                  onPressed: () async {
                    store.playlist.contains(p.slot) ? store.playlist.remove(p.slot) : store.playlist.add(p.slot);
                    await store.save();
                    setState(() {});
                  }),
              IconButton(tooltip: 'Delete from panel', icon: const Icon(Icons.delete_outline), onPressed: () => run('Delete ${p.slot}', () async {
                    final r = await s.device.deleteSlots([p.slot]);
                    await store.remove(p.slot);
                    setState(() {});
                    return r;
                  })),
            ]),
          ),
        ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
          onPressed: () async {
            final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(title: const Text('Erase every stored program on the panel?'), actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Erase')),
                    ]));
            if (ok != true) return;
            await run('Erase all', () async {
              final r = await s.device.deleteAll();
              await store.clear();
              setState(() {});
              return r;
            });
          },
          icon: const Icon(Icons.delete_forever),
          label: const Text('Erase all on panel')),
      statusBar(context),
    ]);
  }
}
