import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:meta/meta.dart';
import 'package:native_toolchain_rust/src/config_mapping.dart';
import 'package:native_toolchain_rust/src/exception.dart';
import 'package:path/path.dart' as path;

@internal
interface class BuildEnvironmentFactory {
  const BuildEnvironmentFactory();

  Map<String, String> createBuildEnvVars(CodeConfig codeConfig) {
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
        ),
    };
  }
}

@internal
interface class AndroidBuildEnvironmentFactory {
  const AndroidBuildEnvironmentFactory();

  Map<String, String> createBuildEnvVars({required CodeConfig codeConfig}) {
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

    // Keep the existing NDK >=27 compatibility check independent of the
    // minimum Android API requested by the hook invoker.
    getBinaryPath('${ndkTargetTriple}35-clang');
    getBinaryPath('${ndkTargetTriple}35-clang++');

    // Target-specific wrappers also supply the API level to native compilation
    // and linking. A higher level can make the library incompatible with the
    // application's declared minimum SDK.
    final apiTarget = codeConfig.android.targetNdkApi;
    final clangPath = getBinaryPath('$ndkTargetTriple$apiTarget-clang');
    final clangPpPath = getBinaryPath('$ndkTargetTriple$apiTarget-clang++');
    final ranlibPath = getBinaryPath('llvm-ranlib', windowsSuffix: 'exe');

    final ndkToolchainRoot = path.dirname(path.dirname(clangPath));
    final sysroot = path.join(ndkToolchainRoot, 'sysroot');
    final extraInclude = '$sysroot/usr/include/$ndkSysrootTargetTriple';
    final bindgenClangArgs = '--sysroot=$sysroot -I$extraInclude'
        // NOTE: force the use of forward-slash path separators
        .replaceAll(r'\', '/');

    return {
      'AR_$targetTripleEnvVar': path.fromUri(cCompiler.archiver),
      'CC_$targetTripleEnvVar': clangPath,
      'CXX_$targetTripleEnvVar': clangPpPath,
      'RANLIB_$targetTripleEnvVar': ranlibPath,
      'CARGO_TARGET_${targetTripleEnvVar.toUpperCase()}_LINKER': clangPath,
      'BINDGEN_EXTRA_CLANG_ARGS_$targetTripleEnvVar': bindgenClangArgs,
    };
  }
}
