import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eir/app_settings.dart';
import 'package:eir/main.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    MediaKit.ensureInitialized();
    await LiquidGlassWidgets.initialize();
    await AppSettings.instance.init();
  });

  testWidgets('EirApp root smoke test mounts successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const EirApp());
    // Session initialization runs asynchronously on mount; pump bounded frames until settled
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('创建专属放映室').evaluate().isNotEmpty ||
          find.text('客户端初始化失败').evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byType(EirApp), findsOneWidget);
  });
}
