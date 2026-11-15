import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:meta/meta.dart';
import 'package:native_toolchain_rust/src/config_mapping.dart';
import 'package:native_toolchain_rust/src/exception.dart';
import 'package:path/path.dart' as path;
import 'package:toml/toml.dart';

@internal
interface class BuildEnvironmentFactory {
  const BuildEnvironmentFactory();

  /// Creates the environment variables for `cargo build`.
  ///
  /// [userEnvironment] is the environment Cargo will otherwise see
  /// (including the builder's extra Cargo environment variables), and
  /// [cargoConfigSearchDirectories] are the directories whose ancestors
  /// may contain a Cargo configuration file.
  Map<String, String> createBuildEnvVars(
    CodeConfig codeConfig, {
    Map<String, String> userEnvironment = const {},
    List<String> cargoConfigSearchDirectories = const [],
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
          userEnvironment: userEnvironment,
          cargoConfigSearchDirectories: cargoConfigSearchDirectories,
        ),
    };
  }
}

@internal
interface class AndroidBuildEnvironmentFactory {
  const AndroidBuildEnvironmentFactory();

  /// The linker argument that aligns ELF segments on 16 KB pages.
  ///
  /// Google Play requires the 64 bit native libraries of apps targeting
  /// Android 15 or later to support 16 KB page sizes.
  /// NDK r28 and later already do this by default, but older NDKs align on
  /// 4 KB, and Flutter may hand the build hook an older NDK
  /// (e.g., the one in `ANDROID_NDK_HOME`).
  /// See: https://developer.android.com/guide/practices/page-sizes
  static const pageSizeLinkArg = '-Wl,-z,max-page-size=16384';

  /// Environment variables that set [pageSizeLinkArg] for [targetTriple].
  ///
  /// The flag is only set when the user has not configured any rustflags
  /// that would conflict with it, because setting
  /// `CARGO_TARGET_<triple>_RUSTFLAGS` makes Cargo ignore `build.rustflags`,
  /// and is ignored itself when `RUSTFLAGS` is set.
  /// Users who configure rustflags themselves should add the flag
  /// themselves too.
  @visibleForTesting
  static Map<String, String> createPageSizeEnvVars({
    required String targetTriple,
    required Map<String, String> userEnvironment,
    required Iterable<File> cargoConfigFiles,
  }) {
    const pageSizeTargets = {'aarch64-linux-android', 'x86_64-linux-android'};
    if (!pageSizeTargets.contains(targetTriple)) return const {};

    final targetRustflagsEnvVar =
        'CARGO_TARGET_${targetTriple.replaceAll('-', '_').toUpperCase()}'
        '_RUSTFLAGS';
    final conflictingEnvVars = {
      'RUSTFLAGS',
      'CARGO_ENCODED_RUSTFLAGS',
      'CARGO_BUILD_RUSTFLAGS',
      targetRustflagsEnvVar,
    };
    if (conflictingEnvVars.any(userEnvironment.containsKey) ||
        cargoConfigFiles.any(_configuresRustflags)) {
      return const {};
    }

    return {targetRustflagsEnvVar: '-C link-arg=$pageSizeLinkArg'};
  }

  /// The Cargo configuration files that Cargo may read when it is invoked
  /// from any of [searchDirectories], in no particular order.
  ///
  /// This may include files Cargo will not actually read, which only means
  /// that the 16 KB page size flag is left for the user to set.
  /// See: https://doc.rust-lang.org/cargo/reference/config.html#hierarchical-structure
  @visibleForTesting
  static Iterable<File> findCargoConfigFiles({
    required List<String> searchDirectories,
    required Map<String, String> userEnvironment,
  }) {
    final home = userEnvironment['HOME'] ?? userEnvironment['USERPROFILE'];
    final cargoHome =
        userEnvironment['CARGO_HOME'] ??
        (home != null ? path.join(home, '.cargo') : null);

    Iterable<String> ancestors(String directory) sync* {
      var current = path.normalize(path.absolute(directory));
      while (true) {
        yield current;
        final parent = path.dirname(current);
        if (parent == current) return;
        current = parent;
      }
    }

    final configDirectories = <String>{
      for (final directory in searchDirectories)
        for (final ancestor in ancestors(directory))
          path.join(ancestor, '.cargo'),
      ?cargoHome,
    };
    return [
      for (final directory in configDirectories)
        for (final name in ['config.toml', 'config'])
          File(path.join(directory, name)),
    ].where((file) => file.existsSync());
  }

  static bool _configuresRustflags(File configFile) {
    final Map<String, dynamic> config;
    try {
      config = TomlDocument.parse(configFile.readAsStringSync()).toMap();
    } on Object {
      // NOTE: if we can't tell, assume the user configures rustflags
      return true;
    }

    bool hasRustflags(Object? table) =>
        table is Map && table.containsKey('rustflags');
    final targets = config['target'];
    return hasRustflags(config['build']) ||
        (targets is Map && targets.values.any(hasRustflags));
  }

  Map<String, String> createBuildEnvVars({
    required CodeConfig codeConfig,
    Map<String, String> userEnvironment = const {},
    List<String> cargoConfigSearchDirectories = const [],
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
      ...createPageSizeEnvVars(
        targetTriple: targetTriple,
        userEnvironment: userEnvironment,
        cargoConfigFiles: findCargoConfigFiles(
          searchDirectories: cargoConfigSearchDirectories,
          userEnvironment: userEnvironment,
        ),
      ),
    };
  }
}
