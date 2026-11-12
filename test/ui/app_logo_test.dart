import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eir/widgets/app_logo.dart';
import 'package:eir/app_settings.dart';

void main() {
  testWidgets('AppLogo builds and renders with primary theme color without error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppLogo(size: 32, useGradient: false, hasGlow: false),
          ),
        ),
      ),
    );

    expect(find.byType(AppLogo), findsOneWidget);
  });

  testWidgets('AppLogo renders with gradient mode and glow', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppLogo(size: 48, useGradient: true, hasGlow: true),
          ),
        ),
      ),
    );

    expect(find.byType(AppLogo), findsOneWidget);
  });
}
