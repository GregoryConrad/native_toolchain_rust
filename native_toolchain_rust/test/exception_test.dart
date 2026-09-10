import 'package:native_toolchain_rust/src/exception.dart';
import 'package:test/test.dart';

void main() {
  group('RustValidationException', () {
    test('compose returns results when no exceptions are thrown', () {
      final results = RustValidationException.compose([() => 1, () => 2]);
      expect(results, equals([1, 2]));
    });

    test('compose throws aggregate exception', () {
      expect(
        () => RustValidationException.compose([
          () => throw const RustValidationException(['error1']),
          () => 1,
          () => throw const RustValidationException(['error2', 'error3']),
        ]),
        throwsA(
          isA<RustValidationException>().having(
            (e) => e.validationErrors,
            'validationErrors',
            equals(['error1', 'error2', 'error3']),
          ),
        ),
      );
    });

    test('compose does not catch other exceptions', () {
      expect(
        () => RustValidationException.compose([
          () => throw Exception('some other error'),
        ]),
        throwsA(isA<Exception>()),
      );
    });
  });
}
