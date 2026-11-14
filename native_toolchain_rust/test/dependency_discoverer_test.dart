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
        unorderedEquals([
          path.toUri('src/lib.rs'),
          path.toUri('/path/to/some/other/file.rs'),
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
        unorderedEquals([
          path.toUri('src/lib.rs'),
          path.toUri('/path/to/some/other/file.rs'),
        ]),
      );
    });

    test('discover handles an empty dependency file', () {
      final dependencyFilePath = path.join(tempDir.path, 'test.d');
      File(dependencyFilePath).writeAsStringSync('');

      final dependencies = dependencyDiscoverer.discover(dependencyFilePath);

      expect(dependencies, isEmpty);
    });

    test('discover does not include the dependency file itself', () {
      // Cargo refreshes the mtime of the dep-info file on every invocation,
      // even for no-op rebuilds. Including it in the dependency list causes
      // Flutter's build graph to emit "File modified during build. Build
      // must be rerun." warnings. See issue #73.
      final dependencyFilePath = path.join(tempDir.path, 'test.d');
      File(
        dependencyFilePath,
      ).writeAsStringSync('target/debug/librust_lib.a: src/lib.rs');

      final dependencies = dependencyDiscoverer.discover(dependencyFilePath);

      expect(dependencies, isNot(contains(path.toUri(dependencyFilePath))));
    });

    test('discover correctly parses paths with escaped spaces and '
        'line continuations', () {
      final dependencyFilePath = path.join(tempDir.path, 'test.d');
      File(dependencyFilePath).writeAsStringSync(
        'target/debug/librust_lib.a: src/lib.rs '
        r'C:\Users\John\ Doe\lib.rs'
        '\n'
        'target/debug/librust_lib.a: /path/with\\ space/mod.rs \\\n'
        '  /continuation/path.rs',
      );

      final dependencies = dependencyDiscoverer.discover(dependencyFilePath);

      expect(
        dependencies,
        unorderedEquals([
          path.toUri('src/lib.rs'),
          path.toUri(r'C:\Users\John Doe\lib.rs'),
          path.toUri('/path/with space/mod.rs'),
          path.toUri('/continuation/path.rs'),
        ]),
      );
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
