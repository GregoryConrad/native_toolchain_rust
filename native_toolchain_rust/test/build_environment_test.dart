import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/src/build_environment.dart';
import 'package:native_toolchain_rust/src/exception.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('AndroidBuildEnvironmentFactory', () {
    late Directory temporaryDirectory;
    late Directory binaries;
    const factory = AndroidBuildEnvironmentFactory();

    File tool(String name, {String windowsSuffix = 'cmd'}) {
      final filename = Platform.isWindows ? '$name.$windowsSuffix' : name;
      return File(path.join(binaries.path, filename))..createSync();
    }

    void compilers(String triple, int api) {
      tool('$triple$api-clang');
      tool('$triple$api-clang++');
    }

    CodeConfig config(Architecture architecture, int api) {
      final builder = BuildInputBuilder()
        ..setupShared(
          packageRoot: temporaryDirectory.uri,
          packageName: 'test_package',
          outputDirectoryShared: temporaryDirectory.uri.resolve('output/'),
          outputFile: temporaryDirectory.uri.resolve('output.json'),
        )
        ..addExtension(
          CodeAssetExtension(
            targetArchitecture: architecture,
            targetOS: OS.android,
            linkModePreference: LinkModePreference.dynamic,
            android: AndroidCodeConfig(targetNdkApi: api),
            cCompiler: CCompilerConfig(
              compiler: tool('clang', windowsSuffix: 'exe').uri,
              linker: tool('ld', windowsSuffix: 'exe').uri,
              archiver: tool('llvm-ar', windowsSuffix: 'exe').uri,
            ),
          ),
        );
      return builder.build().config.code;
    }

    setUp(() {
      temporaryDirectory = Directory.systemTemp.createTempSync(
        'android_build_environment_test',
      );
      binaries = Directory(path.join(temporaryDirectory.path, 'bin'))
        ..createSync();
      tool('llvm-ranlib', windowsSuffix: 'exe');
    });

    tearDown(() {
      temporaryDirectory.deleteSync(recursive: true);
    });

    for (final (architecture, rustTriple, ndkTriple, api) in [
      (
        Architecture.arm64,
        'aarch64-linux-android',
        'aarch64-linux-android',
        24,
      ),
      (
        Architecture.arm,
        'armv7-linux-androideabi',
        'armv7a-linux-androideabi',
        26,
      ),
    ]) {
      test('honors API $api for $rustTriple', () {
        compilers(ndkTriple, 35);
        compilers(ndkTriple, api);
        final environment = factory.createBuildEnvVars(
          codeConfig: config(architecture, api),
        );
        final key = rustTriple.replaceAll('-', '_');

        expect(environment['CC_$key'], tool('$ndkTriple$api-clang').path);
        expect(environment['CXX_$key'], tool('$ndkTriple$api-clang++').path);
        expect(
          environment['CARGO_TARGET_${key.toUpperCase()}_LINKER'],
          environment['CC_$key'],
        );
      });
    }

    test(
      'does not fall back to API 35 when the requested compiler is absent',
      () {
        compilers('aarch64-linux-android', 35);
        final input = config(Architecture.arm64, 24);

        expect(
          () => factory.createBuildEnvVars(codeConfig: input),
          throwsA(isA<RustValidationException>()),
        );
      },
    );

    test('preserves the existing NDK compatibility check', () {
      compilers('aarch64-linux-android', 24);
      final input = config(Architecture.arm64, 24);

      expect(
        () => factory.createBuildEnvVars(codeConfig: input),
        throwsA(isA<RustValidationException>()),
      );
    });

    test('aligns 64 bit libraries on 16 KB pages by default', () {
      compilers('aarch64-linux-android', 35);
      compilers('aarch64-linux-android', 24);
      final environment = factory.createBuildEnvVars(
        codeConfig: config(Architecture.arm64, 24),
      );

      expect(
        environment['CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS'],
        '-C link-arg=-Wl,-z,max-page-size=16384',
      );
    });

    test('leaves the 32 bit target alone', () {
      compilers('armv7a-linux-androideabi', 35);
      compilers('armv7a-linux-androideabi', 24);
      final environment = factory.createBuildEnvVars(
        codeConfig: config(Architecture.arm, 24),
      );

      expect(environment.keys, isNot(contains(endsWith('_RUSTFLAGS'))));
    });
  });

  group('AndroidBuildEnvironmentFactory.createPageSizeEnvVars', () {
    late Directory temporaryDirectory;

    setUp(() {
      temporaryDirectory = Directory.systemTemp.createTempSync(
        'android_page_size_test',
      );
    });

    tearDown(() {
      temporaryDirectory.deleteSync(recursive: true);
    });

    File configFile(String contents) {
      return File(path.join(temporaryDirectory.path, 'config.toml'))
        ..writeAsStringSync(contents);
    }

    Map<String, String> pageSizeEnvVars({
      String targetTriple = 'x86_64-linux-android',
      Map<String, String> userEnvironment = const {},
      List<File> cargoConfigFiles = const [],
    }) {
      return AndroidBuildEnvironmentFactory.createPageSizeEnvVars(
        targetTriple: targetTriple,
        userEnvironment: userEnvironment,
        cargoConfigFiles: cargoConfigFiles,
      );
    }

    test('sets the flag when nothing conflicts', () {
      expect(
        pageSizeEnvVars(cargoConfigFiles: [configFile('[net]\nretry = 3\n')]),
        {
          'CARGO_TARGET_X86_64_LINUX_ANDROID_RUSTFLAGS':
              '-C link-arg=-Wl,-z,max-page-size=16384',
        },
      );
    });

    for (final envVar in [
      'RUSTFLAGS',
      'CARGO_ENCODED_RUSTFLAGS',
      'CARGO_BUILD_RUSTFLAGS',
      'CARGO_TARGET_X86_64_LINUX_ANDROID_RUSTFLAGS',
    ]) {
      test('defers to the user when $envVar is set', () {
        expect(pageSizeEnvVars(userEnvironment: {envVar: '--cfg x'}), isEmpty);
      });
    }

    for (final (description, contents) in [
      ('build.rustflags', '[build]\nrustflags = ["--cfg", "x"]\n'),
      (
        'target.<triple>.rustflags',
        '[target.x86_64-linux-android]\nrustflags = ["--cfg", "x"]\n',
      ),
      (
        'target.<cfg>.rustflags',
        "[target.'cfg(target_os = \"android\")']\nrustflags = []\n",
      ),
      ('an unparsable config', '[build\n'),
    ]) {
      test('defers to the user when a Cargo config has $description', () {
        expect(
          pageSizeEnvVars(cargoConfigFiles: [configFile(contents)]),
          isEmpty,
        );
      });
    }
  });

  group('AndroidBuildEnvironmentFactory.findCargoConfigFiles', () {
    late Directory temporaryDirectory;

    setUp(() {
      temporaryDirectory = Directory.systemTemp.createTempSync(
        'cargo_config_files_test',
      );
    });

    tearDown(() {
      temporaryDirectory.deleteSync(recursive: true);
    });

    File createFile(List<String> parts) {
      return File(path.joinAll([temporaryDirectory.path, ...parts]))
        ..createSync(recursive: true);
    }

    test('finds configs in ancestors and CARGO_HOME', () {
      final projectConfig = createFile(['project', '.cargo', 'config.toml']);
      final legacyConfig = createFile(['.cargo', 'config']);
      final homeConfig = createFile(['cargo_home', 'config.toml']);
      Directory(
        path.join(temporaryDirectory.path, 'project', 'rust'),
      ).createSync(recursive: true);

      final files = AndroidBuildEnvironmentFactory.findCargoConfigFiles(
        searchDirectories: [
          path.join(temporaryDirectory.path, 'project', 'rust'),
        ],
        userEnvironment: {
          'CARGO_HOME': path.join(temporaryDirectory.path, 'cargo_home'),
        },
      ).map((file) => path.canonicalize(file.path));

      expect(
        files,
        containsAll([
          path.canonicalize(projectConfig.path),
          path.canonicalize(legacyConfig.path),
          path.canonicalize(homeConfig.path),
        ]),
      );
    });
  });
}
