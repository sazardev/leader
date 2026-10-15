import 'package:test/test.dart';

void main() {
  group('calc', () {
    group('add', () {
      test('sums', () {
        expect(1 + 1, 2);
      });
      test('fails', () {
        print('debug line');
        expect(1 + 1, 3);
      });
    });
    test('throws', () {
      throw StateError('boom');
    });
    test('skipped', () {}, skip: 'later');
  });
}
