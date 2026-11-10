import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:eir/webrtc_validation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('WebRTC loopback data channel', (tester) async {
    final result = await runWebRtcLoopback();
    debugPrint(result.toString());
    debugPrint('statsTypes=${result.statsTypes}');
    debugPrint('fingerprintFields=${result.fingerprintFields}');
    expect(result.success, isTrue);
    expect(result.messageValidated, isTrue);
    expect(result.binaryValidated, isTrue);
    expect(result.statsReportCount, greaterThan(0));
    expect(result.remoteDtlsFingerprint, isNotEmpty);
    expect(result.callbackErrors, isEmpty);
  });
}
