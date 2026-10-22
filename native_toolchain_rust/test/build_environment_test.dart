import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/src/build_environment.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('AndroidBuildEnvironmentFactory.linkerFlags', () {
    test('asks for 16 KB pages on the 64 bit targets', () {
      for (final targetTriple in [
        'aarch64-linux-android',
        'x86_64-linux-android',
      ]) {
        expect(
          AndroidBuildEnvironmentFactory.linkerFlags(targetTriple),
          equals(['-Wl,-z,max-page-size=16384']),
        );
      }
    });

    test('adds nothing on the 32 bit target', () {
      expect(
        AndroidBuildEnvironmentFactory.linkerFlags('armv7-linux-androideabi'),
        isEmpty,
      );
    });
  });

  group('AndroidBuildEnvironmentFactory.linkerWrapperScript', () {
    test('puts the flags before the arguments in a POSIX script', () {
      expect(
        AndroidBuildEnvironmentFactory.linkerWrapperScript(
          linker: "/ndk/it's/clang",
          flags: ['-a', '-b'],
          isWindows: false,
        ),
        equals(
          '#!/bin/sh\n'
          "exec '/ndk/it'\\''s/clang' '-a' '-b' \"\$@\"\n",
        ),
      );
    });

    test('puts the flags before the arguments in a Windows script', () {
      expect(
        AndroidBuildEnvironmentFactory.linkerWrapperScript(
          linker: r'C:\ndk 100%\clang.cmd',
          flags: ['-a', '-b'],
          isWindows: true,
        ),
        equals(
          '@echo off\r\n'
          '"C:\\ndk 100%%\\clang.cmd" -a -b %*\r\n',
        ),
      );
    });
  });

  group('AndroidBuildEnvironmentFactory.createBuildEnvVars', () {
    late Directory tempDir;
    late String ndkBinDir;
    late String outputDirectory;

    String ndkBinary(String name, {String windowsSuffix = 'cmd'}) {
      return path.join(
        ndkBinDir,
        OS.current == OS.windows ? '$name.$windowsSuffix' : name,
      );
    }

    CodeConfig androidCodeConfig(Architecture targetArchitecture) {
      final inputBuilder = BuildInputBuilder()
        ..setupShared(
          packageRoot: tempDir.uri,
          packageName: 'test_package',
          outputDirectoryShared: tempDir.uri.resolve('shared/'),
          outputFile: tempDir.uri.resolve('output.json'),
        )
        ..config.setupBuild(linkingEnabled: false);
      CodeAssetExtension(
        targetArchitecture: targetArchitecture,
        targetOS: OS.android,
        linkModePreference: LinkModePreference.dynamic,
        cCompiler: CCompilerConfig(
          archiver: path.toUri(path.join(ndkBinDir, 'llvm-ar')),
          compiler: path.toUri(path.join(ndkBinDir, 'clang')),
          linker: path.toUri(path.join(ndkBinDir, 'ld.lld')),
        ),
        android: AndroidCodeConfig(targetNdkApi: 30),
      ).setupBuildInput(inputBuilder);
      return inputBuilder.build().config.code;
    }

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync();
      ndkBinDir = path.join(tempDir.path, 'ndk', 'bin');
      outputDirectory = path.join(tempDir.path, 'output');
      Directory(ndkBinDir).createSync(recursive: true);
      for (final ndkTargetTriple in [
        'aarch64-linux-android',
        'armv7a-linux-androideabi',
        'x86_64-linux-android',
      ]) {
        File(ndkBinary('${ndkTargetTriple}35-clang')).createSync();
        File(ndkBinary('${ndkTargetTriple}35-clang++')).createSync();
      }
      File(ndkBinary('llvm-ranlib', windowsSuffix: 'exe')).createSync();
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('links the 64 bit targets through a wrapper adding the flags', () {
      for (final (architecture, triple) in [
        (Architecture.arm64, 'aarch64-linux-android'),
        (Architecture.x64, 'x86_64-linux-android'),
      ]) {
        final envVars = const AndroidBuildEnvironmentFactory()
            .createBuildEnvVars(
              codeConfig: androidCodeConfig(architecture),
              outputDirectory: outputDirectory,
            );
        final tripleEnvVar = triple.replaceAll('-', '_');
        final linker =
            envVars['CARGO_TARGET_${tripleEnvVar.toUpperCase()}_LINKER']!;

        expect(path.isWithin(outputDirectory, linker), isTrue);
        expect(
          File(linker).readAsStringSync(),
          equals(
            AndroidBuildEnvironmentFactory.linkerWrapperScript(
              linker: envVars['CC_$tripleEnvVar']!,
              flags: ['-Wl,-z,max-page-size=16384'],
              isWindows: OS.current == OS.windows,
            ),
          ),
        );
        expect(envVars.keys, everyElement(isNot(contains('RUSTFLAGS'))));
      }
    });

    test('links the 32 bit target with clang directly', () {
      final envVars = const AndroidBuildEnvironmentFactory().createBuildEnvVars(
        codeConfig: androidCodeConfig(Architecture.arm),
        outputDirectory: outputDirectory,
      );

      expect(
        envVars['CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER'],
        equals(envVars['CC_armv7_linux_androideabi']),
      );
      expect(Directory(outputDirectory).existsSync(), isFalse);
    });

    test('the wrapper runs clang with the flags, then the given arguments', () {
      final clangPath = ndkBinary('aarch64-linux-android35-clang');
      File(clangPath).writeAsStringSync('#!/bin/sh\nprintf "%s\\n" "\$@"\n');
      Process.runSync('chmod', ['+x', clangPath]);

      final envVars = const AndroidBuildEnvironmentFactory().createBuildEnvVars(
        codeConfig: androidCodeConfig(Architecture.arm64),
        outputDirectory: outputDirectory,
      );
      final result = Process.runSync(
        envVars['CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER']!,
        ['-o', 'lib with spaces.so', r"it's $HOME"],
      );

      expect(result.exitCode, equals(0));
      expect(
        (result.stdout as String).split('\n'),
        equals([
          '-Wl,-z,max-page-size=16384',
          '-o',
          'lib with spaces.so',
          r"it's $HOME",
          '',
        ]),
      );
    }, testOn: 'posix');
  });
}
