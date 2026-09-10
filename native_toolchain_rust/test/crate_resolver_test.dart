import 'dart:io';

import 'package:native_toolchain_rust/src/crate_resolver.dart';
import 'package:native_toolchain_rust/src/exception.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('CrateDirectoryResolver', () {
    late Directory tempDir;
    const resolver = CrateDirectoryResolver();

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('crate_resolver_test');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('resolveCrateDirectory returns the correct directory', () {
      final crateDir = Directory(path.join(tempDir.path, 'crate'))
        ..createSync();

      final result = resolver.resolveCrateDirectory(
        rootPath: tempDir.path,
        cratePathOptions: ['crate'],
      );

      expect(result.path, equals(crateDir.path));
    });

    test('resolveCrateDirectory throws RustValidationException '
        'if no directory exists', () {
      expect(
        () => resolver.resolveCrateDirectory(
          rootPath: tempDir.path,
          cratePathOptions: ['non_existent_crate'],
        ),
        throwsA(isA<RustValidationException>()),
      );
    });

    test('resolveCrateDirectory returns the first existing directory', () {
      final crateDir1 = Directory(path.join(tempDir.path, 'crate1'));
      final crateDir2 = Directory(path.join(tempDir.path, 'crate2'));
      crateDir1.createSync();
      crateDir2.createSync();

      final result = resolver.resolveCrateDirectory(
        rootPath: tempDir.path,
        cratePathOptions: ['crate1', 'crate2'],
      );

      expect(result.path, equals(crateDir1.path));
    });
  });
}
