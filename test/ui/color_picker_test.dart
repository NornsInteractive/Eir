import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eir/views/color_picker_dialog.dart';
import 'package:eir/app_settings.dart';

void main() {
  testWidgets('LiquidGlassColorPicker renders and selects arbitrary color via HEX input', (tester) async {
    Color? selectedColor;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                selectedColor = await showLiquidGlassColorPicker(
                  context,
                  initialColor: const Color(0xFF007AFF),
                  title: '选取主题色',
                );
              },
              child: const Text('Open Picker'),
            ),
          ),
        ),
      ),
    );

    // Open picker
    await tester.tap(find.text('Open Picker'));
    await tester.pumpAndSettle();

    expect(find.text('选取主题色'), findsOneWidget);
    expect(find.byKey(const ValueKey('color-picker-hex-input')), findsOneWidget);

    // Input new HEX: #FF5722 (Deep Orange)
    await tester.enterText(find.byKey(const ValueKey('color-picker-hex-input')), 'FF5722');
    await tester.pumpAndSettle();

    // Tap Apply
    await tester.tap(find.byKey(const ValueKey('color-picker-apply-btn')));
    await tester.pumpAndSettle();

    expect(selectedColor, isNotNull);
    expect(selectedColor!.value, equals(const Color(0xFFFF5722).value));
  });

  testWidgets('LiquidGlassColorPicker swatches update current color', (tester) async {
    Color? selectedColor;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                selectedColor = await showLiquidGlassColorPicker(
                  context,
                  initialColor: const Color(0xFF007AFF),
                  title: '选取主题色',
                );
              },
              child: const Text('Open Picker'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Picker'));
    await tester.pumpAndSettle();

    // Tap emerald swatch: Color(0xFF30D158)
    final emeraldFinder = find.byWidgetPredicate(
      (w) => w is AnimatedContainer && (w.decoration as BoxDecoration?)?.color == const Color(0xFF30D158),
    );
    expect(emeraldFinder, findsOneWidget);
    await tester.tap(emeraldFinder);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('color-picker-apply-btn')));
    await tester.pumpAndSettle();

    expect(selectedColor, isNotNull);
    expect(selectedColor!.value, equals(const Color(0xFF30D158).value));
  });
}
