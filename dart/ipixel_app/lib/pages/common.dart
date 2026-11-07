import 'package:flutter/material.dart';

/// Panel colors offered in pickers.
const panelColors = <Color>[
  Colors.black, Colors.white, Colors.red, Colors.orange, Colors.amber, Colors.green, Colors.cyan, Colors.blue, Colors.purple,
];

/// 0xRRGGBB int for the fx engine.
int colorToInt(Color c) => ((c.r * 255).round() << 16) | ((c.g * 255).round() << 8) | (c.b * 255).round();

List<int> colorToRgb(Color c) => [(c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round()];

class ColorRow extends StatelessWidget {
  final Color value;
  final ValueChanged<Color> onChanged;
  const ColorRow({super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in panelColors)
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => onChanged(c),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                    width: value == c ? 3 : 1,
                    color: value == c ? Theme.of(context).colorScheme.primary : Colors.black26),
              ),
            ),
          ),
      ]);
}

/// Runs an async action and shows its result/error + progress. Mixin for page states.
mixin RunAction<T extends StatefulWidget> on State<T> {
  String status = '';
  double? progress;
  bool busy = false;

  Future<void> run(String label, Future<Object?> Function() f) async {
    if (busy) return;
    setState(() {
      busy = true;
      status = '$label…';
      progress = null;
    });
    try {
      final r = await f();
      if (mounted) setState(() => status = '$label: ${_describe(r)}');
    } catch (e) {
      if (mounted) setState(() => status = '$label failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void onProgress(double v) {
    if (mounted) setState(() => progress = v);
  }

  String _describe(Object? r) => switch (r) {
        3 => 'done ✓',
        1 || true => 'ok ✓',
        0 || false => 'rejected by display',
        null => 'sent',
        _ => '$r',
      };

  Widget statusBar(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (busy) LinearProgressIndicator(value: progress),
        const SizedBox(height: 8),
        Text(status, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

/// Standard page padding/width.
class PageBody extends StatelessWidget {
  final List<Widget> children;
  const PageBody({super.key, required this.children});
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(padding: const EdgeInsets.all(16), children: children),
        ),
      );
}

/// Shows panel-sized RGBA pixels enlarged with crisp edges.
class PixelPreview extends StatelessWidget {
  final dynamic image; // ui.Image?
  final double aspect;
  const PixelPreview({super.key, required this.image, required this.aspect});
  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: aspect,
        child: DecoratedBox(
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(6)),
          child: image == null
              ? const Center(child: Text('no frame yet', style: TextStyle(color: Colors.white54)))
              : RawImage(image: image, fit: BoxFit.fill, filterQuality: FilterQuality.none),
        ),
      );
}
