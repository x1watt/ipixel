// End-to-end on real hardware: run with
//   flutter test integration_test/text_real_test.dart -d linux
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ipixel_app/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('connect + send text from the Text tab', (tester) async {
    await tester.pumpWidget(const IPixelApp());
    // wait for the display to appear in the scan list
    for (var i = 0; i < 100 && find.byType(ListTile).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(ListTile), findsWidgets);
    await tester.pump(const Duration(seconds: 2)); // let the list settle like a human would
    final tile = tester.widget<ListTile>(find.byType(ListTile).first);
    debugPrint('TILE onTap set: ${tile.onTap != null}');
    await tester.tap(find.byType(ListTile).first);
    await tester.pump(const Duration(milliseconds: 500));
    debugPrint('after tap, spinner: ${find.byType(CircularProgressIndicator).evaluate().length}');
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      debugPrint('tap not delivered -> calling onTap directly');
      tester.widget<ListTile>(find.byType(ListTile).first).onTap?.call();
    }
    for (var i = 0; i < 200 && find.text('Send').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (i % 25 == 0) {
        debugPrint('SCREEN[$i]: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(' | ')}');
      }
    }
    debugPrint('connected, Text tab visible: ${find.text('Send').evaluate().isNotEmpty}');
    await tester.enterText(find.byType(TextField).first, 'E2E ok');
    await tester.tap(find.text('Send'));
    String status = '';
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      status = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '')
          .firstWhere((s) => s.startsWith('Text:') || s.startsWith('Text failed'), orElse: () => '');
      if (status.isNotEmpty) break;
    }
    debugPrint('E2E STATUS: "$status"');
    expect(status, contains('done'));
  });
}
