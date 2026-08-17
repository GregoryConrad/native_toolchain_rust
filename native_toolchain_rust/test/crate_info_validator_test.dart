import 'package:mocktail/mocktail.dart';
import 'package:native_toolchain_rust/src/crate_info_validator.dart';
import 'package:native_toolchain_rust/src/exception.dart';
import 'package:native_toolchain_rust/src/toml_parsing.dart';
import 'package:test/test.dart';

class MockCargoManifestParser extends Mock implements CargoManifestParser {}

class MockToolchainTomlParser extends Mock implements ToolchainTomlParser {}

void main() {
  group('CrateInfoValidator', () {
    late CrateInfoValidator validator;
    late MockToolchainTomlParser mockToolchainTomlParser;
    late MockCargoManifestParser mockCargoManifestParser;

    setUp(() {
      mockToolchainTomlParser = MockToolchainTomlParser();
      mockCargoManifestParser = MockCargoManifestParser();
      validator = CrateInfoValidator(
        toolchainTomlParser: mockToolchainTomlParser,
        cargoManifestParser: mockCargoManifestParser,
      );
    });

    test('fetchAndValidateCrateInfo returns correct info on success', () {
      when(() => mockCargoManifestParser.parseManifest(any())).thenReturn(
        const CargoManifest(
          crateName: 'my_crate',
          libCrateTypes: ['staticlib', 'cdylib'],
        ),
      );
      when(() => mockToolchainTomlParser.parseToolchainToml(any())).thenReturn((
        channel: '1.90.0',
        targets: {'aarch64-linux-android'},
      ));

      final result = validator.fetchAndValidateCrateInfo(
        manifestPath: 'dummy_manifest_path',
        toolchainTomlPath: 'dummy_toolchain_path',
        targetTriple: 'aarch64-linux-android',
      );

      expect(result.crateName, 'my_crate');
      expect(result.toolchainChannel, '1.90.0');
    });

    test('fetchAndValidateCrateInfo throws exception on validation issues', () {
      when(() => mockCargoManifestParser.parseManifest(any())).thenReturn(
        const CargoManifest(
          crateName: 'my_crate',
          libCrateTypes: ['staticlib'],
        ),
      );
      when(() => mockToolchainTomlParser.parseToolchainToml(any())).thenReturn((
        channel: 'stable',
        targets: {'x86_64-linux-gnu'},
      ));

      expect(
        () => validator.fetchAndValidateCrateInfo(
          manifestPath: 'dummy_manifest_path',
          toolchainTomlPath: 'dummy_toolchain_path',
          targetTriple: 'aarch64-linux-android',
        ),
        throwsA(
          isA<RustValidationException>().having(
            (e) => e.validationErrors,
            'validationErrors',
            equals([
              '''
Your Cargo.toml must specify [staticlib, cdylib] under `lib.crate-types`.
For more information, see https://github.com/GregoryConrad/native_toolchain_rust?tab=readme-ov-file#cargotoml''',
              '''
The rust-toolchain.toml is using the `stable` channel, which is not allowed.
Please specify an exact version (e.g., `1.90.0`) to ensure a reproducible build.
For more information, see https://github.com/GregoryConrad/native_toolchain_rust?tab=readme-ov-file#rust-toolchaintoml''',
              '''
The rust-toolchain.toml does not include the target `aarch64-linux-android`.
If you wish to support this target, please add it to the `targets` array in the rust-toolchain.toml file.
For more information, see https://github.com/GregoryConrad/native_toolchain_rust?tab=readme-ov-file#rust-toolchaintoml''',
            ]),
          ),
        ),
      );
    });
  });
}
