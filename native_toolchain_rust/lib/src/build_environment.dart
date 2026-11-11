import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:meta/meta.dart';
import 'package:native_toolchain_rust/src/config_mapping.dart';
import 'package:native_toolchain_rust/src/exception.dart';
import 'package:path/path.dart' as path;

@internal
interface class BuildEnvironmentFactory {
  const BuildEnvironmentFactory();

  Map<String, String> createBuildEnvVars(
    CodeConfig codeConfig, {
    required String outputDirectory,
  }) {
    return {
      // NOTE: XCode makes some injections into PATH that break host build
      // for crates with a build.rs
      // See also: https://github.com/irondash/native_toolchain_rust/issues/17
      if (Platform.isMacOS) ...{
        'PATH': Platform.environment['PATH']!
            .split(':')
            .where((e) => !e.contains('Contents/Developer/'))
            .join(':'),
      },

      if (codeConfig.targetOS == OS.android)
        ...const AndroidBuildEnvironmentFactory().createBuildEnvVars(
          codeConfig: codeConfig,
          outputDirectory: outputDirectory,
        ),
    };
  }
}

@internal
interface class AndroidBuildEnvironmentFactory {
  const AndroidBuildEnvironmentFactory();

  /// Linker flags passed for [targetTriple], before the arguments from rustc.
  ///
  /// Google Play requires the 64 bit native libraries of apps targeting
  /// Android 15 or later to support 16 KB page sizes.
  /// NDK r28 and later already align ELF segments on 16 KB by default,
  /// but older NDKs align them on 4 KB.
  /// See: https://developer.android.com/guide/practices/page-sizes
  ///
  /// NOTE: LLD keeps the last `max-page-size` it is given, and these flags
  /// come before the arguments from rustc, so a value set by the user
  /// (e.g., via `-C link-arg=-Wl,-z,max-page-size=...`) still takes precedence.
  /// The flags must not need any quoting (the Windows script has them as-is).
  @visibleForTesting
  static List<String> linkerFlags(String targetTriple) {
    return switch (targetTriple) {
      'aarch64-linux-android' ||
      'x86_64-linux-android' => const ['-Wl,-z,max-page-size=16384'],
      _ => const [],
    };
  }

  /// The contents of a script that invokes [linker] with [flags]
  /// followed by all of the arguments the script itself was given.
  @visibleForTesting
  static String linkerWrapperScript({
    required String linker,
    required List<String> flags,
    required bool isWindows,
  }) {
    if (isWindows) {
      // NOTE: there is intentionally no `call` here, as it would double any ^
      // in the arguments; control passes to the NDK's own .cmd instead,
      // so the exit code is the same as when rustc runs that .cmd directly.
      final escapedLinker = linker.replaceAll('%', '%%');
      return [
        '@echo off',
        '"$escapedLinker" ${flags.join(' ')} %*',
        '',
      ].join('\r\n');
    }

    String quote(String arg) => "'${arg.replaceAll("'", r"'\''")}'";
    return [
      '#!/bin/sh',
      'exec ${[linker, ...flags].map(quote).join(' ')} "\$@"',
      '',
    ].join('\n');
  }

  Map<String, String> createBuildEnvVars({
    required CodeConfig codeConfig,
    required String outputDirectory,
  }) {
    final CodeConfig(:targetTriple, :cCompiler) = codeConfig;
    if (cCompiler == null) {
      throw UnsupportedError(
        'CCompilerConfig was not provided but is required for $targetTriple',
      );
    }

    String getBinaryPath(String binaryName, {String windowsSuffix = 'cmd'}) {
      final compilerBinariesDir = path.dirname(
        path.fromUri(cCompiler.compiler),
      );
      final binaryPath = path.join(
        compilerBinariesDir,
        (OS.current == OS.windows) ? '$binaryName.$windowsSuffix' : binaryName,
      );

      if (!File(binaryPath).existsSync()) {
        throw RustValidationException([
          'Binary $binaryPath not found; is your installed NDK too old?',
        ]);
      }

      return binaryPath;
    }

    final targetTripleEnvVar = targetTriple.replaceAll('-', '_');
    final ndkTargetTriple = switch (targetTriple) {
      // NOTE: sometimes the Rust and NDK target triples do not match.
      // See: https://github.com/GregoryConrad/native_toolchain_rust/issues/21#issuecomment-3368307228
      'armv7-linux-androideabi' => 'armv7a-linux-androideabi',
      _ => targetTriple,
    };
    final ndkSysrootTargetTriple = switch (targetTriple) {
      // NOTE: sometimes the Rust and NDK sysroot target triples do not match.
      'armv7-linux-androideabi' => 'arm-linux-androideabi',
      _ => targetTriple,
    };

    // NOTE: we need to point to NDK >=27 vended LLVM for Android.
    // The `${ndkTargetTriple}35-clang`s were introduced in NDK 27,
    // so using these binaries:
    // 1. Ensures we are using a compatible NDK
    // 2. Also fixes build issues when just using the `clang`s directly
    const apiTarget = '35';
    final clangPath = getBinaryPath('$ndkTargetTriple$apiTarget-clang');
    final clangPpPath = getBinaryPath('$ndkTargetTriple$apiTarget-clang++');
    final ranlibPath = getBinaryPath('llvm-ranlib', windowsSuffix: 'exe');

    final ndkToolchainRoot = path.dirname(path.dirname(clangPath));
    final sysroot = path.join(ndkToolchainRoot, 'sysroot');
    final extraInclude = '$sysroot/usr/include/$ndkSysrootTargetTriple';
    final bindgenClangArgs = '--sysroot=$sysroot -I$extraInclude'
        // NOTE: force the use of forward-slash path separators
        .replaceAll(r'\', '/');

    // NOTE: extra linker flags go through a small wrapper script around clang
    // instead of through rustflags, since any rustflags set here would replace
    // or disable the user's own (e.g., Cargo ignores `build.rustflags`
    // as soon as a `target.<triple>.rustflags` is set).
    final extraLinkerFlags = linkerFlags(targetTriple);
    final linkerPath = extraLinkerFlags.isEmpty
        ? clangPath
        : _createLinkerWrapper(
            directory: outputDirectory,
            targetTriple: targetTriple,
            linker: clangPath,
            flags: extraLinkerFlags,
          );

    return {
      'AR_$targetTripleEnvVar': path.fromUri(cCompiler.archiver),
      'CC_$targetTripleEnvVar': clangPath,
      'CXX_$targetTripleEnvVar': clangPpPath,
      'RANLIB_$targetTripleEnvVar': ranlibPath,
      'CARGO_TARGET_${targetTripleEnvVar.toUpperCase()}_LINKER': linkerPath,
      'BINDGEN_EXTRA_CLANG_ARGS_$targetTripleEnvVar': bindgenClangArgs,
    };
  }

  String _createLinkerWrapper({
    required String directory,
    required String targetTriple,
    required String linker,
    required List<String> flags,
  }) {
    // NOTE: the name ends with `-clang` so that rustc,
    // which infers the linker flavor from the linker's name,
    // treats the wrapper the same as the NDK's clang
    final isWindows = OS.current == OS.windows;
    final wrapper = File(
      path.join(directory, '$targetTriple-clang${isWindows ? '.cmd' : ''}'),
    );
    final contents = linkerWrapperScript(
      linker: linker,
      flags: flags,
      isWindows: isWindows,
    );

    // NOTE: only (re)write the wrapper when its contents change
    if (wrapper.existsSync() && wrapper.readAsStringSync() == contents) {
      return wrapper.path;
    }

    wrapper.parent.createSync(recursive: true);
    wrapper.writeAsStringSync(contents);
    if (!isWindows) {
      final chmodResult = Process.runSync('chmod', ['+x', wrapper.path]);
      if (chmodResult.exitCode != 0) {
        throw RustProcessException(
          'Failed to make ${wrapper.path} executable: ${chmodResult.stderr}',
        );
      }
    }

    return wrapper.path;
  }
}
