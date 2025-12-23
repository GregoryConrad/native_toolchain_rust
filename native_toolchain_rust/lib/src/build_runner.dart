import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';
import 'package:native_toolchain_rust/src/build_environment.dart';
import 'package:native_toolchain_rust/src/config_mapping.dart';
import 'package:native_toolchain_rust/src/crate_info_validator.dart';
import 'package:native_toolchain_rust/src/crate_resolver.dart';
import 'package:native_toolchain_rust/src/dependency_discoverer.dart';
import 'package:native_toolchain_rust/src/process_runner.dart';
import 'package:path/path.dart' as path;

@internal
interface class RustBuildRunner {
  const RustBuildRunner({
    required this.config,
    required this.logger,
    required this.crateDirectoryResolver,
    required this.processRunner,
    required this.buildEnvironmentFactory,
    required this.crateInfoValidator,
    required this.dependencyDiscoverer,
  });

  final RustBuilder config;
  final Logger logger;
  final CrateDirectoryResolver crateDirectoryResolver;
  final ProcessRunner processRunner;
  final BuildEnvironmentFactory buildEnvironmentFactory;
  final CrateInfoValidator crateInfoValidator;
  final DependencyDiscoverer dependencyDiscoverer;

  Future<void> run({
    required BuildInput input,
    required BuildOutputBuilder output,
    required List<AssetRouting> assetRouting,
  }) async {
    logger
      ..info('Starting build of Rust code assets')
      ..config(input)
      ..config(Platform.environment);

    if (!input.config.buildCodeAssets) {
      logger.info(
        'buildCodeAssets is false; '
        'skipping build of Rust code assets',
      );
      return;
    }

    logger.info('Gathering all data required for the build');
    final codeConfig = input.config.code;
    final CodeConfig(:targetOS, :targetTriple, :linkMode) = codeConfig;
    final RustBuilder(
      :assetName,
      :cratePath,
      :features,
      :enableDefaultFeatures,
      :extraCargoBuildArgs,
      :extraCargoEnvironmentVariables,
      :buildMode,
    ) = config;
    final crateDirectory = crateDirectoryResolver.resolveCrateDirectory(
      rootPath: path.fromUri(input.packageRoot),
      cratePathOptions: cratePath != null ? [cratePath] : ['rust', 'native'],
    );
    final outputDir = path.join(path.fromUri(input.outputDirectory), 'target');
    final manifestPath = path.join(crateDirectory.path, 'Cargo.toml');
    final (
      :crateName,
      :toolchainChannel,
    ) = crateInfoValidator.fetchAndValidateCrateInfo(
      targetTriple: targetTriple,
      manifestPath: manifestPath,
      toolchainTomlPath: path.join(crateDirectory.path, 'rust-toolchain.toml'),
    );

    logger.info('Ensuring $toolchainChannel is installed');
    await ensureToolchainDownloaded(crateDirectory.path);

    logger.info('Running cargo build');
    await processRunner.invokeRustup(
      [
        'run',
        toolchainChannel,
        'cargo',
        'build',
        ...switch (buildMode) {
          BuildMode.release => ['--release'],
          BuildMode.debug => [],
        },
        '--manifest-path',
        manifestPath,
        '--package',
        crateName,
        '--target',
        targetTriple,
        '--target-dir',
        outputDir,
        if (!enableDefaultFeatures) '--no-default-features',
        if (features.isNotEmpty) ...['--features', features.join(',')],
        ...extraCargoBuildArgs,
      ],
      environment: {
        ...buildEnvironmentFactory.createBuildEnvVars(codeConfig),
        ...extraCargoEnvironmentVariables,
      },
    );

    final binaryFilePath = path.join(
      outputDir,
      targetTriple,
      buildMode.name,
      targetOS.libraryFileName(crateName, linkMode).replaceAll('-', '_'),
    );

    // NOTE: re-run build whenever any of the dependencies change
    output.dependencies.addAll(
      dependencyDiscoverer.discover(path.setExtension(binaryFilePath, '.d')),
    );

    for (final routing in assetRouting) {
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: assetName,
          linkMode: linkMode,
          file: path.toUri(binaryFilePath),
        ),
        routing: routing,
      );
    }
  }

  Future<void> ensureToolchainDownloaded(String crateDirectory) async {
    // NOTE: invoking rustup automatically downloads the toolchain
    // in rust-toolchain.toml, if not already downloaded.
    final showToolchainOutput = await processRunner.invokeRustup([
      'show',
      'active-toolchain',
    ], workingDirectory: crateDirectory);
    logger.config(showToolchainOutput);
  }
}
