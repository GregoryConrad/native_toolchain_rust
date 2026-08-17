import 'dart:io';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:native_toolchain_rust/src/exception.dart';
import 'package:toml/toml.dart';

@internal
class CargoManifest {
  const CargoManifest({
    required this.crateName,
    required this.libCrateTypes,
    this.libName,
  });

  final String? libName;
  final String crateName;
  final List<String> libCrateTypes;
}

@internal
interface class TomlDocumentWrapperFactory {
  const TomlDocumentWrapperFactory(this.logger);
  final Logger logger;

  TomlDocumentWrapper parseFile(String filePath) =>
      TomlDocumentWrapper(logger, filePath, TomlDocument.loadSync(filePath));
}

@internal
final class TomlDocumentWrapper {
  const TomlDocumentWrapper(this.logger, this.filePath, this.document);

  final Logger logger;
  final String filePath;
  final TomlDocument document;

  T walk<T>(String path) {
    try {
      dynamic currNode = document.toMap();
      for (final field in path.split('.')) {
        // NOTE: we are traversing this manually, dynamic is a must
        // ignore: avoid_dynamic_calls
        currNode = currNode[field];
      }
      return currNode as T;
    } on Object catch (exception, stackTrace) {
      logger.severe(
        'Failed to find $path in $filePath: $document',
        exception,
        stackTrace,
      );
      throw RustValidationException([
        '''
Could not find the field `$path` in the TOML file at $filePath.
Please ensure the field exists and is correctly formatted.
The following exception was thrown: $exception''',
      ]);
    }
  }
}

@internal
interface class CargoManifestParser {
  const CargoManifestParser(this.logger, this.tomlDocumentFactory);
  final Logger logger;
  final TomlDocumentWrapperFactory tomlDocumentFactory;

  CargoManifest parseManifest(
    String manifestPath,
  ) {
    logger.info('Looking for Cargo.toml');
    if (!File(manifestPath).existsSync()) {
      throw RustValidationException([
        '''
The Cargo.toml file was not found at $manifestPath.
For more information, see https://github.com/GregoryConrad/native_toolchain_rust?tab=readme-ov-file#cargotoml''',
      ]);
    }

    logger.info('Parsing Cargo.toml');
    final TomlDocumentWrapper manifest;
    try {
      manifest = tomlDocumentFactory.parseFile(manifestPath);
    } on Object catch (exception, stackTrace) {
      logger.severe('Failed to parse Cargo.toml', exception, stackTrace);
      throw RustValidationException([
        '''
Failed to parse the Cargo.toml file at $manifestPath.
Please check the file for syntax errors.
For more information, see https://doc.rust-lang.org/cargo/reference/manifest.html
The following exception was thrown: $exception''',
      ]);
    }

    final [
      String? libName,
      String crateName,
      List<String> libCrateTypes,
    ] = RustValidationException.compose<dynamic>([
      () {
        try {
          return manifest.walk<String>('lib.name');
        } on RustValidationException {
          logger.fine(
            '`lib.name` is not defined. Using `package.name` instead',
          );
        }
      },
      () {
        try {
          return manifest.walk<String>('package.name');
        } on RustValidationException {
          throw const RustValidationException([
            '''
The Cargo.toml file must specify the `package.name` field.
For more information, see https://doc.rust-lang.org/cargo/reference/manifest.html#the-name-field''',
          ]);
        }
      },
      () {
        try {
          return manifest.walk<List<dynamic>>('lib.crate-type').cast<String>();
        } on RustValidationException {
          throw const RustValidationException([
            '''
The Cargo.toml file must specify the `lib.crate-type` field.
For more information, see https://github.com/GregoryConrad/native_toolchain_rust?tab=readme-ov-file#cargotoml
and https://doc.rust-lang.org/cargo/reference/cargo-targets.html#the-crate-type-field''',
          ]);
        }
      },
    ]);

    return CargoManifest(
      libName: libName,
      crateName: crateName,
      libCrateTypes: libCrateTypes,
    );
  }
}

@internal
interface class ToolchainTomlParser {
  const ToolchainTomlParser(this.logger, this.tomlDocumentFactory);
  final Logger logger;
  final TomlDocumentWrapperFactory tomlDocumentFactory;

  ({Set<String> targets, String channel}) parseToolchainToml(
    String toolchainTomlPath,
  ) {
    logger.info('Looking for rust-toolchain.toml');
    if (!File(toolchainTomlPath).existsSync()) {
      throw RustValidationException([
        '''
The rust-toolchain.toml file was not found at $toolchainTomlPath.
For more information, see https://github.com/GregoryConrad/native_toolchain_rust?tab=readme-ov-file#rust-toolchaintoml''',
      ]);
    }

    logger.info('Parsing rust-toolchain.toml');
    final TomlDocumentWrapper toolchain;
    try {
      toolchain = tomlDocumentFactory.parseFile(toolchainTomlPath);
    } on Object catch (e, stackTrace) {
      logger.severe('Failed to parse rust-toolchain.toml', e, stackTrace);
      throw RustValidationException([
        '''
Failed to parse the rust-toolchain.toml file at $toolchainTomlPath.
Please check the file for syntax errors.
For more information, see https://github.com/GregoryConrad/native_toolchain_rust?tab=readme-ov-file#rust-toolchaintoml
The following exception was thrown: $e''',
      ]);
    }

    final [
      String channel,
      Set<String> targets,
    ] = RustValidationException.compose<dynamic>([
      () {
        try {
          return toolchain.walk<String>('toolchain.channel');
        } on RustValidationException {
          throw const RustValidationException([
            '''
The rust-toolchain.toml file must specify the `toolchain.channel` field.
For more information, see https://github.com/GregoryConrad/native_toolchain_rust?tab=readme-ov-file#rust-toolchaintoml''',
          ]);
        }
      },
      () {
        try {
          return toolchain
              .walk<List<dynamic>>('toolchain.targets')
              .cast<String>()
              .toSet();
        } on RustValidationException {
          throw const RustValidationException([
            '''
The rust-toolchain.toml file must specify the `toolchain.targets` field.
For more information, see https://github.com/GregoryConrad/native_toolchain_rust?tab=readme-ov-file#rust-toolchaintoml''',
          ]);
        }
      },
    ]);

    return (channel: channel, targets: targets);
  }
}
