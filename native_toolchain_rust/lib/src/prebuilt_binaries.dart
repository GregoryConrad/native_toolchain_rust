import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:native_toolchain_rust/src/exception.dart';
import 'package:native_toolchain_rust/src/toml_parsing.dart';
import 'package:path/path.dart' as path;

/// The name of the (optional) config file that downstream users may place in
/// the root of their project to opt in to downloading prebuilt binaries.
@internal
const prebuiltBinaryConfigFileName = 'native_toolchain_rust.toml';

@internal
interface class RootProjectResolver {
  const RootProjectResolver();

  /// Resolves the root path of the project currently being built.
  String? resolveRootProjectPath(String outputDirectoryPath) {
    final segments = path.split(path.normalize(outputDirectoryPath));
    final dartToolIndex = segments.lastIndexOf('.dart_tool');
    if (dartToolIndex <= 0) return null;
    return path.joinAll(segments.take(dartToolIndex));
  }
}

@internal
interface class PrebuiltBinaryConfigParser {
  const PrebuiltBinaryConfigParser(this.logger, this.tomlDocumentFactory);
  final Logger logger;
  final TomlDocumentWrapperFactory tomlDocumentFactory;

  /// Returns the templated download URL configured for [packageName],
  /// or null if the config file at [configFilePath] does not exist
  /// or does not contain an entry for [packageName].
  String? parseUrlTemplate({
    required String configFilePath,
    required String packageName,
  }) {
    if (!File(configFilePath).existsSync()) {
      logger.info(
        'No $prebuiltBinaryConfigFileName found at $configFilePath; '
        'building from source',
      );
      return null;
    }

    logger.info('Parsing $configFilePath');
    final TomlDocumentWrapper config;
    try {
      config = tomlDocumentFactory.parseFile(configFilePath);
    } on Object catch (exception, stackTrace) {
      logger.severe(
        'Failed to parse $prebuiltBinaryConfigFileName',
        exception,
        stackTrace,
      );
      throw RustValidationException([
        '''
Failed to parse the $prebuiltBinaryConfigFileName file at $configFilePath.
For more information, see https://github.com/GregoryConrad/native_toolchain_rust?tab=readme-ov-file#prebuilt-binaries
The following exception was thrown: $exception''',
      ]);
    }

    final prebuiltBinaries = config.document.toMap()['prebuilt-binaries'];
    final packageEntry = prebuiltBinaries is Map<String, dynamic>
        ? prebuiltBinaries[packageName]
        : null;
    if (prebuiltBinaries == null || packageEntry == null) {
      logger.info(
        'No `prebuilt-binaries.$packageName` entry found in $configFilePath; '
        'building from source',
      );
      return null;
    }

    final urlTemplate = packageEntry is Map<String, dynamic>
        ? packageEntry['url']
        : null;
    if (urlTemplate is! String) {
      throw RustValidationException([
        '''
The `prebuilt-binaries.$packageName` entry in $configFilePath is malformed.
The entry must specify a `url`, for example:
[prebuilt-binaries.$packageName]
url = "https://github.com/some-user/some-repo/releases/download/v{version}/my_crate-{target}.bin"
For more information, see https://github.com/GregoryConrad/native_toolchain_rust?tab=readme-ov-file#prebuilt-binaries''',
      ]);
    }

    return urlTemplate;
  }
}

@internal
interface class PubspecVersionParser {
  const PubspecVersionParser(this.logger);
  final Logger logger;

  static final _versionPattern = RegExp(
    r'''^version:\s*['"]?([^'"#\s]+)''',
  );

  /// Parses the `version` field out of the pubspec.yaml at [pubspecPath].
  String parseVersion(String pubspecPath) {
    logger.info('Looking for the package version in $pubspecPath');
    final pubspecFile = File(pubspecPath);
    if (!pubspecFile.existsSync()) {
      throw RustValidationException([
        'The pubspec.yaml file was not found at $pubspecPath.',
      ]);
    }

    final version = pubspecFile
        .readAsLinesSync()
        .map((line) => _versionPattern.firstMatch(line)?.group(1))
        .nonNulls
        .firstOrNull;
    if (version == null) {
      throw RustValidationException([
        '''
The pubspec.yaml file at $pubspecPath does not specify a `version` field,
which is required to resolve the `{version}` in prebuilt binary download URLs.
For more information, see https://github.com/GregoryConrad/native_toolchain_rust?tab=readme-ov-file#prebuilt-binaries''',
      ]);
    }
    return version;
  }
}

@internal
interface class DownloadUrlResolver {
  const DownloadUrlResolver(this.logger);
  final Logger logger;

  /// Resolves [urlTemplate] into a concrete download [Uri] by substituting
  /// all `{placeholder}`s with their values from [templateValues].
  Uri resolveDownloadUrl({
    required String urlTemplate,
    required Map<String, String> templateValues,
  }) {
    logger.info('Resolving download URL template: $urlTemplate');
    var url = urlTemplate;
    for (final MapEntry(:key, :value) in templateValues.entries) {
      url = url.replaceAll('{$key}', value);
    }

    final unknownPlaceholders = RegExp(
      r'\{[^{}]*\}',
    ).allMatches(url).map((match) => match.group(0)).toList();
    if (unknownPlaceholders.isNotEmpty) {
      throw RustValidationException([
        '''
The prebuilt binary URL template `$urlTemplate` contains unsupported placeholders: $unknownPlaceholders.
The supported placeholders are: ${templateValues.keys.map((key) => '{$key}').join(', ')}.
For more information, see https://github.com/GregoryConrad/native_toolchain_rust?tab=readme-ov-file#prebuilt-binaries''',
      ]);
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !const {'http', 'https'}.contains(uri.scheme)) {
      throw RustValidationException([
        '''
The prebuilt binary URL template `$urlTemplate` resolved to `$url`,
which is not a valid http/https URL.
For more information, see https://github.com/GregoryConrad/native_toolchain_rust?tab=readme-ov-file#prebuilt-binaries''',
      ]);
    }

    logger.info('Resolved download URL: $uri');
    return uri;
  }
}

@internal
interface class PrebuiltBinaryDownloader {
  const PrebuiltBinaryDownloader(this.logger);
  final Logger logger;

  /// Downloads the file at [url] to [destinationPath],
  /// following any redirects along the way.
  ///
  /// The file only ever appears at [destinationPath] in its entirety;
  /// a failed/interrupted download will not leave a corrupt file behind
  /// (which is essential, as [destinationPath] may be in a shared cache).
  Future<void> download({
    required Uri url,
    required String destinationPath,
  }) async {
    logger.info('Downloading prebuilt binary from $url to $destinationPath');
    final client = HttpClient();
    final temporaryFile = File(
      '$destinationPath.$pid.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw RustPrebuiltBinaryException(
          'Failed to download the prebuilt binary from $url; '
          'the server responded with HTTP status code '
          '${response.statusCode}. '
          'Please ensure the URL template in your '
          '$prebuiltBinaryConfigFileName is correct '
          'and that a binary was published for this version and target.',
        );
      }

      temporaryFile.parent.createSync(recursive: true);
      await response.pipe(temporaryFile.openWrite());
      temporaryFile.renameSync(destinationPath);
      logger.info('Finished downloading prebuilt binary to $destinationPath');
    } on IOException catch (exception, stackTrace) {
      logger.severe(
        'Failed to download prebuilt binary from $url',
        exception,
        stackTrace,
      );
      throw RustPrebuiltBinaryException(
        'Failed to download the prebuilt binary from $url; '
        'please check your network connection and the URL template in your '
        '$prebuiltBinaryConfigFileName. '
        'The following exception was thrown: $exception',
      );
    } finally {
      client.close();
      if (temporaryFile.existsSync()) {
        temporaryFile.deleteSync();
      }
    }
  }
}

@internal
interface class PrebuiltBinaryFetcher {
  const PrebuiltBinaryFetcher({
    required this.logger,
    required this.rootProjectResolver,
    required this.configParser,
    required this.pubspecVersionParser,
    required this.downloadUrlResolver,
    required this.downloader,
  });

  final Logger logger;
  final RootProjectResolver rootProjectResolver;
  final PrebuiltBinaryConfigParser configParser;
  final PubspecVersionParser pubspecVersionParser;
  final DownloadUrlResolver downloadUrlResolver;
  final PrebuiltBinaryDownloader downloader;

  /// Checks whether the root project opted in to a prebuilt binary for
  /// [packageName] (via a [prebuiltBinaryConfigFileName] file in its root),
  /// and if so, downloads the binary for [targetTriple].
  ///
  /// Returns the path of the downloaded binary alongside the files the build
  /// hook now depends upon, or null if no prebuilt binary was configured
  /// (in which case the caller should build from source).
  Future<({String binaryFilePath, List<String> dependencies})?> fetch({
    required String packageName,
    required String packageRootPath,
    required String sharedOutputDirectoryPath,
    required String crateName,
    required String targetTriple,
    required OS targetOS,
    required LinkMode linkMode,
  }) async {
    final rootProjectPath = rootProjectResolver.resolveRootProjectPath(
      sharedOutputDirectoryPath,
    );
    if (rootProjectPath == null) {
      logger.info(
        'Could not resolve the root project from $sharedOutputDirectoryPath; '
        'skipping the prebuilt binary check and building from source',
      );
      return null;
    }

    final configFilePath = path.join(
      rootProjectPath,
      prebuiltBinaryConfigFileName,
    );
    final urlTemplate = configParser.parseUrlTemplate(
      configFilePath: configFilePath,
      packageName: packageName,
    );
    if (urlTemplate == null) return null;

    logger.info(
      'Found a prebuilt binary configuration for $packageName '
      'in $configFilePath',
    );

    final pubspecPath = path.join(packageRootPath, 'pubspec.yaml');
    // The crate name with `-` normalized to `_`, matching how Cargo names the
    // library it produces.
    final normalizedCrateName = crateName.replaceAll('-', '_');
    final libraryFileName = targetOS.libraryFileName(
      normalizedCrateName,
      linkMode,
    );
    final url = downloadUrlResolver.resolveDownloadUrl(
      urlTemplate: urlTemplate,
      templateValues: {
        'version': pubspecVersionParser.parseVersion(pubspecPath),
        'target': targetTriple,
        'crate-name': normalizedCrateName,
      },
    );

    // NOTE: binaries are cached in the (config-independent) shared output
    // directory, keyed by their resolved download URL. A new package version
    // or an edited URL template yields a new URL (and thus a fresh download),
    // while build hook re-runs with an unchanged URL reuse the cached binary.
    final urlChecksum = sha256.convert(utf8.encode(url.toString()));
    final binaryFilePath = path.join(
      sharedOutputDirectoryPath,
      'prebuilt',
      urlChecksum.toString(),
      libraryFileName,
    );
    if (File(binaryFilePath).existsSync()) {
      logger.info('Reusing the cached prebuilt binary at $binaryFilePath');
    } else {
      await downloader.download(url: url, destinationPath: binaryFilePath);
    }

    // NOTE: re-run the build hook whenever the prebuilt binary config
    // (download URL) or the package version may have changed.
    return (
      binaryFilePath: binaryFilePath,
      dependencies: [configFilePath, pubspecPath],
    );
  }
}
