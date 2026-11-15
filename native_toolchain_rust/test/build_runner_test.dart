import 'package:native_toolchain_rust/src/build_runner.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('resolveCargoTargetDirectory', () {
    const defaultDirectory = '/hook/output/target';

    test('uses the default directory when CARGO_TARGET_DIR is not set', () {
      expect(
        resolveCargoTargetDirectory(
          defaultDirectory: defaultDirectory,
          extraCargoEnvironmentVariables: const {},
          processEnvironment: const {'PATH': '/usr/bin'},
        ),
        defaultDirectory,
      );
    });

    test('uses CARGO_TARGET_DIR from the process environment', () {
      expect(
        resolveCargoTargetDirectory(
          defaultDirectory: defaultDirectory,
          extraCargoEnvironmentVariables: const {},
          processEnvironment: const {'CARGO_TARGET_DIR': '/short/target'},
        ),
        path.absolute('/short/target'),
      );
    });

    test('prefers CARGO_TARGET_DIR from extraCargoEnvironmentVariables', () {
      expect(
        resolveCargoTargetDirectory(
          defaultDirectory: defaultDirectory,
          extraCargoEnvironmentVariables: const {
            'CARGO_TARGET_DIR': '/from/builder',
          },
          processEnvironment: const {'CARGO_TARGET_DIR': '/from/process'},
        ),
        path.absolute('/from/builder'),
      );
    });

    test('ignores an empty CARGO_TARGET_DIR', () {
      expect(
        resolveCargoTargetDirectory(
          defaultDirectory: defaultDirectory,
          extraCargoEnvironmentVariables: const {'CARGO_TARGET_DIR': ''},
          processEnvironment: const {},
        ),
        defaultDirectory,
      );
    });

    test('resolves a relative CARGO_TARGET_DIR to an absolute path', () {
      expect(
        resolveCargoTargetDirectory(
          defaultDirectory: defaultDirectory,
          extraCargoEnvironmentVariables: const {'CARGO_TARGET_DIR': 'target'},
          processEnvironment: const {},
        ),
        path.absolute('target'),
      );
    });
  });
}
