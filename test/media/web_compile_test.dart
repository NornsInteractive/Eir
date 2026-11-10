import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:eir/media/local_media_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web branch compiles + service constructs', () async {
    final svc = LocalMediaService(sendControl: (_) {}, sendBinary: (_) async {}, bufferedAmount: () => 0, localDeviceId: 'c' * 64);
    final m = await svc.registerFile(XFile.fromData(Uint8List.fromList(List<int>.generate(1000, (i) => i % 251)), name: 'a.mp4', mimeType: 'video/mp4'));
    expect(m.size, 1000);
    await svc.dispose();
  });
}
