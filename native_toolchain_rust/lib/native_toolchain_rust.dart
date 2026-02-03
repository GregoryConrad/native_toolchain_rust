import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:native_toolchain_rust/src/build_environment.dart';
import 'package:native_toolchain_rust/src/build_runner.dart';
import 'package:native_toolchain_rust/src/crate_info_validator.dart';
import 'package:native_toolchain_rust/src/crate_resolver.dart';
import 'package:native_toolchain_rust/src/dependency_discoverer.dart';
import 'package:native_toolchain_rust/src/process_runner.dart';
import 'package:native_toolchain_rust/src/toml_parsing.dart';

export 'package:native_toolchain_rust/src/exception.dart';

/// The mode to build the Rust crate with.
enum BuildMode {
  /// Build in release mode; i.e., `cargo build --release`
  release,

  /// Build in debug mode; i.e., a regular `cargo build`
  debug,
}

/// Builds a Rust project via `rustup`.
final class RustBuilder implements Builder {
  /// Creates a [RustBuilder] with the supplied configuration.
  const RustBuilder({
    required this.assetName,
    this.cratePath,
    this.buildMode = BuildMode.release,
    this.enableDefaultFeatures = true,
    this.features = const <String>[],
    this.extraCargoBuildArgs = const <String>[],
    this.extraCargoEnvironmentVariables = const <String, String>{},
  });

  /// The name of the native asset to build.
  ///
  /// For an example, this will often look like: `'src/my_crate_bindings.dart'`
  final String assetName;

  /// The path, from the root of your Dart project, to the Rust crate.
  /// A `Cargo.toml` and `rust-toolchain.toml` are expected at this location.
  ///
  /// If not specified, first tries `rust`, and if that doesn't work, `native`.
  final String? cratePath;

  /// The mode to build the crate with.
  ///
  /// You normally should leave this as the default, [BuildMode.release],
  /// unless you have a _very_ strong reason not to.
  final BuildMode buildMode;

  /// Whether or not to enable the default features of the crate.
  final bool enableDefaultFeatures;

  /// List of features to enable in the crate.
  final List<String> features;

  /// # WARNING
  /// This field is experimental!
  /// It may change on any new release without notice!
  /// Please file an issue with your use-case for it, if you do use it.
  ///
  /// Extra arguments passed to `cargo build`. Often not needed.
  @experimental
  final List<String> extraCargoBuildArgs;

  /// # WARNING
  /// This field is experimental!
  /// It may change on any new release without notice!
  /// Please file an issue with your use-case for it, if you do use it.
  ///
  /// Extra environment variables to set for `cargo build`. Often not needed.
  @experimental
  final Map<String, String> extraCargoEnvironmentVariables;

  /// Runs the entire Rust build process, including:
  /// - Some pre-build validation checks
  /// - Running `cargo build`
  /// - Outputting a [CodeAsset] with the resultant static/dynamic library
  // NOTE: this is essentially impossible to unit test without exposing
  // some ugly @visibleForTesting-marked API.
  // Thus, we defer to RustBuildRunner for unit testing purposes.
  // This class itself will be integration tested.
  @override
  Future<void> run({
    required BuildInput input,
    required BuildOutputBuilder output,
    List<AssetRouting> assetRouting = const [ToAppBundle()],
    Logger? logger,
  }) {
    logger ??= _createDefaultLogger();
    final processRunner = ProcessRunner(logger);
    const crateDirectoryResolver = CrateDirectoryResolver();
    final tomlDocumentWrapperFactory = TomlDocumentWrapperFactory(logger);
    final cargoManifestParser = CargoManifestParser(
      logger,
      tomlDocumentWrapperFactory,
    );
    final toolchainTomlParser = ToolchainTomlParser(
      logger,
      tomlDocumentWrapperFactory,
    );
    const buildEnvironmentFactory = BuildEnvironmentFactory();
    final crateInfoValidator = CrateInfoValidator(
      toolchainTomlParser: toolchainTomlParser,
      cargoManifestParser: cargoManifestParser,
    );
    final dependencyDiscoverer = DependencyDiscoverer(logger);

    return RustBuildRunner(
      config: this,
      logger: logger,
      processRunner: processRunner,
      crateDirectoryResolver: crateDirectoryResolver,
      buildEnvironmentFactory: buildEnvironmentFactory,
      crateInfoValidator: crateInfoValidator,
      dependencyDiscoverer: dependencyDiscoverer,
    ).run(input: input, output: output, assetRouting: assetRouting);
  }
}

Logger _createDefaultLogger() {
  return Logger.detached('RustBuilder')
    ..level = Level.CONFIG
    ..onRecord.listen((record) {
      final output = record.level >= Level.WARNING ? stderr : stdout;

      // NOTE: this is an unreadable mess with cascade notation
      // ignore: cascade_invocations
      output.writeln(record);

      if (record.error != null) {
        output.writeln(record.error);
      }
      if (record.stackTrace != null) {
        output.writeln(record.stackTrace);
      }
    });
}
