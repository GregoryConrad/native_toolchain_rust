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
  });
}
