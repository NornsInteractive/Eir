import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:eir/core/canonical.dart';

void main() {
  group('canonicalBytes', () {
    test('sorts map keys by UTF-8 byte order', () {
      final bytes = canonicalBytes({'b': 1, 'a': 2, 'aa': 3, 'ab': 4});
      expect(utf8.decode(bytes), '{"a":2,"aa":3,"ab":4,"b":1}');
    });

    test('deterministic golden vector', () {
      final bytes = canonicalBytes({
        'z': <Object?>[],
        'a': '中',
        'nested': {'y': null, 'x': [true, false]},
        'i': 42,
      });
      expect(
        utf8.decode(bytes),
        '{"a":"中","i":42,"nested":{"x":[true,false],"y":null},"z":[]}',
      );
    });

    test('rejects floating point values anywhere', () {
      expect(() => canonicalBytes({'x': 1.5}), throwsA(isA<CanonicalValueError>()));
      expect(
        () => canonicalBytes({'x': [1, 2.5]}),
        throwsA(isA<CanonicalValueError>()),
      );
      expect(
        () => canonicalBytes({'x': {'y': 1.0}}),
        throwsA(isA<CanonicalValueError>()),
      );
    });

    test('rejects integers beyond JSON safe range', () {
      expect(
        () => canonicalBytes({'x': kMaxCanonicalInt + 1}),
        throwsA(isA<CanonicalValueError>()),
      );
      expect(
        () => canonicalBytes({'x': -(kMaxCanonicalInt + 1)}),
        throwsA(isA<CanonicalValueError>()),
      );
      expect(() => canonicalBytes({'x': kMaxCanonicalInt}), returnsNormally);
    });

    test('rejects control characters in strings and keys', () {
      expect(
        () => canonicalBytes({'x': 'a\x01b'}),
        throwsA(isA<CanonicalValueError>()),
      );
      expect(
        () => canonicalBytes({'x\x7fy': 'ok'}),
        throwsA(isA<CanonicalValueError>()),
      );
      expect(
        () => canonicalBytes({'ok': 'line\nbreak'}),
        throwsA(isA<CanonicalValueError>()),
      );
    });

    test('rejects non-string map keys', () {
      expect(
        () => canonicalBytes({1: 'x'}),
        throwsA(isA<CanonicalValueError>()),
      );
    });

    test('rejects unsupported types', () {
      expect(() => canonicalBytes({'x': Object()}),
          throwsA(isA<CanonicalValueError>()));
    });
  });

  group('decodeCanonical', () {
    test('round-trips canonical structures', () {
      const wire = '{"a":[1,"x",null,true],"b":{"c":"中"}}';
      final decoded = decodeCanonical(utf8.encode(wire));
      expect(decoded, isA<Map>());
      final map = decoded as Map<String, Object?>;
      expect(map['a'], [1, 'x', null, true]);
      expect((map['b'] as Map)['c'], '中');
    });
  });

  group('domainSeparate', () {
    test('produces purpose-prefixed bytes', () {
      final bytes = domainSeparate('invite', utf8.encode('{}'));
      expect(utf8.decode(bytes), 'EirSign/v1/invite\n{}');
    });

    test('rejects invalid purposes', () {
      expect(() => domainSeparate('Invite!', utf8.encode('{}')),
          throwsA(isA<CanonicalValueError>()));
      expect(() => domainSeparate('', utf8.encode('{}')),
          throwsA(isA<CanonicalValueError>()));
    });
  });

  group('canonicalHashHex', () {
    test('is stable for identical inputs', () {
      final a = canonicalHashHex({'a': 1, 'b': [2, 3]});
      final b = canonicalHashHex({'b': [2, 3], 'a': 1});
      expect(a, b);
      expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });
}
