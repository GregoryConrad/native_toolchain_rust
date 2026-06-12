import 'package:dart_only_prebuilt_binaries_example/dart_only_prebuilt_binaries_example.dart';
import 'package:test/test.dart';

void main() {
  test('rust_multiply correctly multiplies', () {
    expect(rust_multiply(2, 3), equals(6));
  });
}
