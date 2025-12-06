import 'dart:io';

import 'package:logging/logging.dart';
import 'package:native_toolchain_rust/src/dependency_discoverer.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('DependencyDiscoverer', () {
    late DependencyDiscoverer dependencyDiscoverer;
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync();
      dependencyDiscoverer = DependencyDiscoverer(Logger.detached(''));
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('discover returns dependencies from a valid dependency file', () {
      final dependencyFilePath = path.join(tempDir.path, 'test.d');
      File(dependencyFilePath).writeAsStringSync(
        'target/debug/librust_lib.a: src/lib.rs /path/to/some/other/file.rs',
      );

      final dependencies = dependencyDiscoverer.discover(dependencyFilePath);

      expect(
        dependencies,
        containsAll([
          path.toUri('src/lib.rs'),
          path.toUri('/path/to/some/other/file.rs'),
          path.toUri(dependencyFilePath),
        ]),
      );
    });

    test('discover handles multiple lines in the dependency file', () {
      final dependencyFilePath = path.join(tempDir.path, 'test.d');
      File(dependencyFilePath).writeAsStringSync('''
target/debug/librust_lib.a: src/lib.rs
target/debug/librust_lib.a: /path/to/some/other/file.rs
''');

      final dependencies = dependencyDiscoverer.discover(dependencyFilePath);

      expect(
        dependencies,
        containsAll([
          path.toUri('src/lib.rs'),
          path.toUri('/path/to/some/other/file.rs'),
          path.toUri(dependencyFilePath),
        ]),
      );
    });

    test('discover ignores lines without a colon', () {
      final dependencyFilePath = path.join(tempDir.path, 'test.d');
      File(dependencyFilePath).writeAsStringSync('''
invalid line
target/debug/librust_lib.a: src/lib.rs
''');

      final dependencies = dependencyDiscoverer.discover(dependencyFilePath);

      expect(
        dependencies,
        containsAll([
          path.toUri('src/lib.rs'),
          path.toUri(dependencyFilePath),
        ]),
      );
      expect(dependencies.length, 2);
    });

    test('discover handles an empty dependency file', () {
      final dependencyFilePath = path.join(tempDir.path, 'test.d');
      File(dependencyFilePath).writeAsStringSync('');

      final dependencies = dependencyDiscoverer.discover(dependencyFilePath);

      expect(
        dependencies,
        containsAll([
          path.toUri(dependencyFilePath),
        ]),
      );
      expect(dependencies.length, 1);
    });

    test(
      'discover throws an exception if the dependency file is not found',
      () {
        final dependencyFilePath = path.join(tempDir.path, 'non_existent.d');
        expect(
          () => dependencyDiscoverer.discover(dependencyFilePath),
          throwsA(isA<PathNotFoundException>()),
        );
      },
    );
  });
}
