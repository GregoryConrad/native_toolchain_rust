import 'dart:async';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:logging/logging.dart';
import 'package:mocktail/mocktail.dart';
import 'package:native_toolchain_rust/src/exception.dart';
import 'package:native_toolchain_rust/src/prebuilt_binaries.dart';
import 'package:native_toolchain_rust/src/toml_parsing.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

class MockRootProjectResolver extends Mock implements RootProjectResolver {}

class MockPrebuiltBinaryConfigParser extends Mock
    implements PrebuiltBinaryConfigParser {}

class MockPubspecVersionParser extends Mock implements PubspecVersionParser {}

class MockDownloadUrlResolver extends Mock implements DownloadUrlResolver {}

class MockPrebuiltBinaryDownloader extends Mock
    implements PrebuiltBinaryDownloader {}

void main() {
  final logger = Logger.detached('prebuilt_binaries_test');

  group('RootProjectResolver', () {
    const resolver = RootProjectResolver();

    test('resolveRootProjectPath returns the parent of .dart_tool', () {
      final outputDirectory = path.join(
        path.separator,
        'home',
        'user',
        'my_app',
        '.dart_tool',
        'hooks_runner',
        'shared',
        'some_package',
        'out',
      );

      expect(
        resolver.resolveRootProjectPath(outputDirectory),
        path.join(path.separator, 'home', 'user', 'my_app'),
      );
    });

    test('resolveRootProjectPath returns null when .dart_tool is absent', () {
      final outputDirectory = path.join(
        path.separator,
        'home',
        'user',
        'somewhere_else',
      );

      expect(resolver.resolveRootProjectPath(outputDirectory), isNull);
    });
  });

  group('PrebuiltBinaryConfigParser', () {
    late Directory tempDir;
    late String configFilePath;
    late PrebuiltBinaryConfigParser parser;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('prebuilt_config_test');
      configFilePath = path.join(tempDir.path, prebuiltBinaryConfigFileName);
      parser = PrebuiltBinaryConfigParser(
        logger,
        TomlDocumentWrapperFactory(logger),
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('parseUrlTemplate returns null when config file does not exist', () {
      expect(
        parser.parseUrlTemplate(
          configFilePath: configFilePath,
          packageName: 'my_package',
        ),
        isNull,
      );
    });

    test('parseUrlTemplate returns null when package has no entry', () {
      File(configFilePath).writeAsStringSync('''
[prebuilt-binaries.other_package]
url = "https://example.com/{version}/{target}"
''');

      expect(
        parser.parseUrlTemplate(
          configFilePath: configFilePath,
          packageName: 'my_package',
        ),
        isNull,
      );
    });

    test('parseUrlTemplate returns the configured url template', () {
      File(configFilePath).writeAsStringSync('''
[prebuilt-binaries.my_package]
url = "https://example.com/{version}/{target}"
''');

      expect(
        parser.parseUrlTemplate(
          configFilePath: configFilePath,
          packageName: 'my_package',
        ),
        'https://example.com/{version}/{target}',
      );
    });

    test(
      'parseUrlTemplate throws RustValidationException on malformed toml',
      () {
        File(configFilePath).writeAsStringSync('not [valid toml');

        expect(
          () => parser.parseUrlTemplate(
            configFilePath: configFilePath,
            packageName: 'my_package',
          ),
          throwsA(isA<RustValidationException>()),
        );
      },
    );

    test(
      'parseUrlTemplate throws RustValidationException on a malformed entry',
      () {
        File(configFilePath).writeAsStringSync('''
[prebuilt-binaries]
my_package = "https://example.com/{version}/{target}"
''');

        expect(
          () => parser.parseUrlTemplate(
            configFilePath: configFilePath,
            packageName: 'my_package',
          ),
          throwsA(isA<RustValidationException>()),
        );
      },
    );
  });

  group('PubspecVersionParser', () {
    late Directory tempDir;
    late String pubspecPath;
    late PubspecVersionParser parser;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pubspec_version_test');
      pubspecPath = path.join(tempDir.path, 'pubspec.yaml');
      parser = PubspecVersionParser(logger);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('parseVersion returns the version field', () {
      File(pubspecPath).writeAsStringSync('''
name: my_package
version: 1.2.3+4
''');

      expect(parser.parseVersion(pubspecPath), '1.2.3+4');
    });

    test('parseVersion handles quotes and trailing comments', () {
      File(pubspecPath).writeAsStringSync('''
name: my_package
version: "1.2.3" # some comment
''');

      expect(parser.parseVersion(pubspecPath), '1.2.3');
    });

    test(
      'parseVersion throws RustValidationException when file is missing',
      () {
        expect(
          () => parser.parseVersion(pubspecPath),
          throwsA(isA<RustValidationException>()),
        );
      },
    );

    test(
      'parseVersion throws RustValidationException when version is missing',
      () {
        File(pubspecPath).writeAsStringSync('name: my_package');

        expect(
          () => parser.parseVersion(pubspecPath),
          throwsA(isA<RustValidationException>()),
        );
      },
    );
  });

  group('DownloadUrlResolver', () {
    final resolver = DownloadUrlResolver(logger);

    test('resolveDownloadUrl substitutes all placeholders', () {
      final url = resolver.resolveDownloadUrl(
        urlTemplate:
            'https://github.com/u/r/releases/download/v{version}'
            '/{target}-{crate-name}',
        templateValues: {
          'version': '1.2.3',
          'target': 'aarch64-apple-darwin',
          'crate-name': 'my_crate',
        },
      );

      expect(
        url,
        Uri.parse(
          'https://github.com/u/r/releases/download/v1.2.3'
          '/aarch64-apple-darwin-my_crate',
        ),
      );
    });

    test(
      'resolveDownloadUrl throws RustValidationException '
      'on unknown placeholders',
      () {
        expect(
          () => resolver.resolveDownloadUrl(
            urlTemplate: 'https://example.com/{typo}',
            templateValues: {'version': '1.2.3'},
          ),
          throwsA(isA<RustValidationException>()),
        );
      },
    );

    test(
      'resolveDownloadUrl throws RustValidationException '
      'on non-http(s) URLs',
      () {
        expect(
          () => resolver.resolveDownloadUrl(
            urlTemplate: 'file:///etc/passwd',
            templateValues: {'version': '1.2.3'},
          ),
          throwsA(isA<RustValidationException>()),
        );
      },
    );
  });

  group('PrebuiltBinaryDownloader', () {
    late Directory tempDir;
    late HttpServer server;
    late Uri serverUri;
    final downloader = PrebuiltBinaryDownloader(logger);

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('downloader_test');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverUri = Uri.parse('http://localhost:${server.port}');
      server.listen((request) {
        switch (request.uri.path) {
          case '/binary':
            request.response.add([1, 2, 3, 4]);
          case '/redirect':
            unawaited(
              request.response.redirect(serverUri.replace(path: '/binary')),
            );
            return;
          default:
            request.response.statusCode = HttpStatus.notFound;
        }
        unawaited(request.response.close());
      });
    });

    tearDown(() async {
      await server.close(force: true);
      tempDir.deleteSync(recursive: true);
    });

    test('download writes the response body to the destination', () async {
      final destinationPath = path.join(tempDir.path, 'nested', 'lib.so');

      await downloader.download(
        url: serverUri.replace(path: '/binary'),
        destinationPath: destinationPath,
      );

      expect(File(destinationPath).readAsBytesSync(), [1, 2, 3, 4]);
    });

    test('download follows redirects', () async {
      final destinationPath = path.join(tempDir.path, 'lib.so');

      await downloader.download(
        url: serverUri.replace(path: '/redirect'),
        destinationPath: destinationPath,
      );

      expect(File(destinationPath).readAsBytesSync(), [1, 2, 3, 4]);
    });

    test(
      'download throws RustPrebuiltBinaryException on non-200 responses',
      () async {
        expect(
          () => downloader.download(
            url: serverUri.replace(path: '/missing'),
            destinationPath: path.join(tempDir.path, 'lib.so'),
          ),
          throwsA(isA<RustPrebuiltBinaryException>()),
        );
      },
    );

    test(
      'download throws RustPrebuiltBinaryException on connection errors',
      () async {
        await server.close(force: true);

        expect(
          () => downloader.download(
            url: serverUri.replace(path: '/binary'),
            destinationPath: path.join(tempDir.path, 'lib.so'),
          ),
          throwsA(isA<RustPrebuiltBinaryException>()),
        );
      },
    );
  });

  group('PrebuiltBinaryFetcher', () {
    late MockRootProjectResolver mockRootProjectResolver;
    late MockPrebuiltBinaryConfigParser mockConfigParser;
    late MockPubspecVersionParser mockPubspecVersionParser;
    late MockDownloadUrlResolver mockDownloadUrlResolver;
    late MockPrebuiltBinaryDownloader mockDownloader;
    late PrebuiltBinaryFetcher fetcher;

    final rootProjectPath = path.join(path.separator, 'home', 'user', 'app');
    final packageRootPath = path.join(path.separator, 'pub', 'my_package');
    final outputDirectoryPath = path.join(rootProjectPath, '.dart_tool', 'o');
    final configFilePath = path.join(
      rootProjectPath,
      prebuiltBinaryConfigFileName,
    );
    final pubspecPath = path.join(packageRootPath, 'pubspec.yaml');

    setUpAll(() {
      registerFallbackValue(Uri());
    });

    setUp(() {
      mockRootProjectResolver = MockRootProjectResolver();
      mockConfigParser = MockPrebuiltBinaryConfigParser();
      mockPubspecVersionParser = MockPubspecVersionParser();
      mockDownloadUrlResolver = MockDownloadUrlResolver();
      mockDownloader = MockPrebuiltBinaryDownloader();
      fetcher = PrebuiltBinaryFetcher(
        logger: logger,
        rootProjectResolver: mockRootProjectResolver,
        configParser: mockConfigParser,
        pubspecVersionParser: mockPubspecVersionParser,
        downloadUrlResolver: mockDownloadUrlResolver,
        downloader: mockDownloader,
      );
    });

    Future<({String binaryFilePath, List<String> dependencies})?> fetch({
      LinkMode? linkMode,
    }) {
      return fetcher.fetch(
        packageName: 'my_package',
        packageRootPath: packageRootPath,
        outputDirectoryPath: outputDirectoryPath,
        crateName: 'my-crate',
        targetTriple: 'x86_64-unknown-linux-gnu',
        targetOS: OS.linux,
        linkMode: linkMode ?? DynamicLoadingBundled(),
      );
    }

    test('fetch returns null when the root project cannot be resolved', () {
      when(
        () => mockRootProjectResolver.resolveRootProjectPath(any()),
      ).thenReturn(null);

      expect(fetch(), completion(isNull));
    });

    test('fetch returns null when no url template is configured', () {
      when(
        () => mockRootProjectResolver.resolveRootProjectPath(any()),
      ).thenReturn(rootProjectPath);
      when(
        () => mockConfigParser.parseUrlTemplate(
          configFilePath: any(named: 'configFilePath'),
          packageName: any(named: 'packageName'),
        ),
      ).thenReturn(null);

      expect(fetch(), completion(isNull));
    });

    test('fetch downloads the binary and returns its path', () async {
      final downloadUrl = Uri.parse(
        'https://example.com/1.2.3/x86_64-unknown-linux-gnu',
      );
      when(
        () => mockRootProjectResolver.resolveRootProjectPath(any()),
      ).thenReturn(rootProjectPath);
      when(
        () => mockConfigParser.parseUrlTemplate(
          configFilePath: any(named: 'configFilePath'),
          packageName: any(named: 'packageName'),
        ),
      ).thenReturn('https://example.com/{version}/{target}');
      when(
        () => mockPubspecVersionParser.parseVersion(any()),
      ).thenReturn('1.2.3');
      when(
        () => mockDownloadUrlResolver.resolveDownloadUrl(
          urlTemplate: any(named: 'urlTemplate'),
          templateValues: any(named: 'templateValues'),
        ),
      ).thenReturn(downloadUrl);
      when(
        () => mockDownloader.download(
          url: any(named: 'url'),
          destinationPath: any(named: 'destinationPath'),
        ),
      ).thenAnswer((_) async {});

      final result = await fetch();

      final expectedBinaryFilePath = path.join(
        outputDirectoryPath,
        'prebuilt',
        'libmy_crate.so',
      );
      expect(result?.binaryFilePath, expectedBinaryFilePath);
      expect(result?.dependencies, [configFilePath, pubspecPath]);
      verify(
        () => mockConfigParser.parseUrlTemplate(
          configFilePath: configFilePath,
          packageName: 'my_package',
        ),
      ).called(1);
      verify(
        () => mockDownloadUrlResolver.resolveDownloadUrl(
          urlTemplate: 'https://example.com/{version}/{target}',
          templateValues: {
            'version': '1.2.3',
            'target': 'x86_64-unknown-linux-gnu',
            'crate-name': 'my_crate',
          },
        ),
      ).called(1);
      verify(
        () => mockDownloader.download(
          url: downloadUrl,
          destinationPath: expectedBinaryFilePath,
        ),
      ).called(1);
    });

    test(
      'fetch resolves the staticlib name when static linking is requested',
      () async {
        when(
          () => mockRootProjectResolver.resolveRootProjectPath(any()),
        ).thenReturn(rootProjectPath);
        when(
          () => mockConfigParser.parseUrlTemplate(
            configFilePath: any(named: 'configFilePath'),
            packageName: any(named: 'packageName'),
          ),
        ).thenReturn('https://example.com/{crate-name}');
        when(
          () => mockPubspecVersionParser.parseVersion(any()),
        ).thenReturn('1.2.3');
        when(
          () => mockDownloadUrlResolver.resolveDownloadUrl(
            urlTemplate: any(named: 'urlTemplate'),
            templateValues: any(named: 'templateValues'),
          ),
        ).thenReturn(Uri.parse('https://example.com/libmy_crate.a'));
        when(
          () => mockDownloader.download(
            url: any(named: 'url'),
            destinationPath: any(named: 'destinationPath'),
          ),
        ).thenAnswer((_) async {});

        final result = await fetch(linkMode: StaticLinking());

        expect(
          result?.binaryFilePath,
          path.join(outputDirectoryPath, 'prebuilt', 'libmy_crate.a'),
        );
        verify(
          () => mockDownloadUrlResolver.resolveDownloadUrl(
            urlTemplate: 'https://example.com/{crate-name}',
            templateValues: {
              'version': '1.2.3',
              'target': 'x86_64-unknown-linux-gnu',
              'crate-name': 'my_crate',
            },
          ),
        ).called(1);
      },
    );
  });
}
