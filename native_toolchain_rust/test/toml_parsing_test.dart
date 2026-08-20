import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_toolchain_rust/src/exception.dart';
import 'package:native_toolchain_rust/src/toml_parsing.dart';
import 'package:test/test.dart';

void main() {
  final logger = Logger.detached('TestLogger');

  group('TomlDocumentWrapper', () {
    late Directory tempDir;
    late String tempFilePath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync();
      tempFilePath = '${tempDir.path}/test.toml';
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('walk returns value when path is valid', () {
      File(tempFilePath).writeAsStringSync('key = "value"\n');
      final factory = TomlDocumentWrapperFactory(logger);
      final wrapper = factory.parseFile(tempFilePath);
      expect(wrapper.walk<String>('key'), 'value');
    });

    test('walk throws RustValidationException when path is invalid', () {
      File(tempFilePath).writeAsStringSync('key = "value"\n');
      final factory = TomlDocumentWrapperFactory(logger);
      final wrapper = factory.parseFile(tempFilePath);
      expect(
        () => wrapper.walk<String>('invalid.path'),
        throwsA(isA<RustValidationException>()),
      );
    });
  });

  group('CargoManifestParser', () {
    final tomlDocumentFactory = TomlDocumentWrapperFactory(logger);
    final parser = CargoManifestParser(logger, tomlDocumentFactory);
    late Directory tempDir;
    late String tempManifestPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync();
      tempManifestPath = '${tempDir.path}/Cargo.toml';
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('parseManifest returns crate/lib name and lib crate types', () {
      File(tempManifestPath).writeAsStringSync('''
[package]
name = "my_crate"

[lib]
name = "my_lib"
crate-type = ["staticlib"]
''');

      final result = parser.parseManifest(tempManifestPath);

      expect(result.crateName, 'my_crate');
      expect(result.libCrateTypes, ['staticlib']);
      expect(result.libName, 'my_lib');
    });

    test('parseManifest does not log error if lib.name missing', () {
      File(tempManifestPath).writeAsStringSync('''
[package]
name = "my_crate"

[lib]
crate-type = ["staticlib"]
''');

      final subscription = logger.onRecord.listen((record) {
        expect(record.level, lessThan(Level.SEVERE));
      });
      addTearDown(subscription.cancel);

      final result = parser.parseManifest(tempManifestPath);

      expect(result.crateName, 'my_crate');
      expect(result.libCrateTypes, ['staticlib']);
      expect(result.libName, isNull);
    });

    test('parseManifest throws when Cargo.toml not found', () {
      expect(
        () => parser.parseManifest('non_existent_Cargo.toml'),
        throwsA(isA<RustValidationException>()),
      );
    });

    test('parseManifest throws when parsing fails', () {
      File(tempManifestPath).writeAsStringSync('invalid toml');

      expect(
        () => parser.parseManifest(tempManifestPath),
        throwsA(isA<RustValidationException>()),
      );
    });
  });

  group('ToolchainTomlParser', () {
    final tomlDocumentFactory = TomlDocumentWrapperFactory(logger);
    final parser = ToolchainTomlParser(logger, tomlDocumentFactory);
    late Directory tempDir;
    late String tempToolchainTomlPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync();
      tempToolchainTomlPath = '${tempDir.path}/rust-toolchain.toml';
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('parseToolchainToml returns channel and targets', () {
      File(tempToolchainTomlPath).writeAsStringSync('''
[toolchain]
channel = "stable"
targets = ["aarch64-apple-darwin"]
''');

      final result = parser.parseToolchainToml(tempToolchainTomlPath);

      expect(result.channel, 'stable');
      expect(result.targets, {'aarch64-apple-darwin'});
    });

    test('parseToolchainToml throws when rust-toolchain.toml not found', () {
      expect(
        () => parser.parseToolchainToml('non_existent_rust-toolchain.toml'),
        throwsA(isA<RustValidationException>()),
      );
    });

    test('parseToolchainToml throws when parsing fails', () {
      File(tempToolchainTomlPath).writeAsStringSync('invalid toml');

      expect(
        () => parser.parseToolchainToml(tempToolchainTomlPath),
        throwsA(isA<RustValidationException>()),
      );
    });
  });
}
