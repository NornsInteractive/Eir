import 'package:flutter_test/flutter_test.dart';
import 'package:eir/core/turn_diagnostic_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TurnDiagnosticService Unit Tests', () {
    test('Empty server address validation', () async {
      final res = await TurnDiagnosticService.probeTurnServer(server: '   ');
      expect(res.success, false);
      expect(res.message, contains('不能为空'));
    });

    test('TurnTestResult model properties', () {
      const res = TurnTestResult(
        success: true,
        message: 'OK',
        rttMs: 250,
        relayAddress: 'candidate:...',
      );
      expect(res.success, true);
      expect(res.message, 'OK');
      expect(res.rttMs, 250);
      expect(res.relayAddress, 'candidate:...');
    });
  });
}
