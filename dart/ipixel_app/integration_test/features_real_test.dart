// End-to-end on real hardware: flutter test integration_test/features_real_test.dart -d linux
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ipixel_app/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester t, int ms) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  String texts(WidgetTester t) => t.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? '').join(' | ');

  testWidgets('fun, draw and tools pages on a real panel', (tester) async {
    await tester.pumpWidget(const IPixelApp());
    for (var i = 0; i < 100 && find.byType(ListTile).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byType(ListTile).first);
    for (var i = 0; i < 100 && find.text('Pick something below').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Pick something below'), findsOneWidget, reason: 'Fun page should be the first rail tab');

    // --- Fun: effect
    await tester.tap(find.text('Effects'));
    await settle(tester, 300);
    await tester.tap(find.text('Plasma'));
    await settle(tester, 4000);
    final funStatus = texts(tester);
    debugPrint('FUN: ${RegExp(r'Plasma · [\d.]+ fps').firstMatch(funStatus)?.group(0)}');
    expect(funStatus, contains('Plasma ·'));

    // --- Fun: game with keyboard input
    await tester.tap(find.text('Games'));
    await settle(tester, 300);
    await tester.tap(find.text('Snake'));
    await settle(tester, 1500);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await settle(tester, 1000);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(tester, 1500);
    expect(texts(tester), contains('Snake ·'));
    await tester.tap(find.text('Stop'));
    await settle(tester, 500);

    // --- Draw live
    await tester.tap(find.text('Draw'));
    await settle(tester, 500);
    await tester.tap(find.text('Draw live on panel'));
    await settle(tester, 2500);
    expect(find.text('Stop live'), findsOneWidget, reason: 'DIY mode should be live');
    final grid = find.byType(CustomPaint).last;
    await tester.tapAt(tester.getTopLeft(grid) + const Offset(20, 20));
    await settle(tester, 500);
    await tester.tap(find.text('Stop live'));
    await settle(tester, 800);

    // --- Tools: clock face
    await tester.tap(find.text('Tools'));
    await settle(tester, 500);
    await tester.tap(find.text('Face 2'));
    await settle(tester, 2500);
    final tools = texts(tester);
    debugPrint('TOOLS: ${RegExp(r'Clock 2[^|]*').firstMatch(tools)?.group(0)}');
    expect(tools, contains('Clock 2: ok'));
  });
}
