import 'dart:io';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

@internal
interface class DependencyDiscoverer {
  const DependencyDiscoverer(this.logger);

  final Logger logger;

  /// Finds all the source dependencies listed in the specified Cargo dep-info
  /// file.
  ///
  /// The dep-info file itself is intentionally **not** included in the result:
  /// Cargo refreshes its mtime on every invocation (even no-op rebuilds), which
  /// causes Flutter's build graph to detect mid-build modifications and emit
  /// `File modified during build. Build must be rerun.` warnings. The source
  /// files parsed out of the dep-info already provide complete change-detection
  /// coverage for incremental rebuilds.
  Iterable<Uri> discover(String dependencyFilePath) {
    logger.fine('Discovering dependencies in $dependencyFilePath');
    final rawContent = File(dependencyFilePath).readAsStringSync();
    // Normalize line continuations (backslash followed by newline).
    final normalized = rawContent.replaceAll(RegExp(r'\\\r?\n'), ' ');
    final result = <Uri>[];
    for (final line in normalized.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final colonIndex = trimmed.indexOf(': ');
      final depsString = colonIndex != -1
          ? trimmed.substring(colonIndex + 2)
          : trimmed;
      // Cargo/Make dep-info escapes spaces in file paths with a backslash ('\ ').
      // Split only on whitespace that is not preceded by a backslash.
      final rawTokens = depsString.split(RegExp(r'(?<!\\) +'));
      for (final token in rawTokens) {
        final unescaped = token.replaceAll(r'\ ', ' ').trim();
        if (unescaped.isNotEmpty) {
          result.add(path.toUri(unescaped));
        }
      }
    }
    return result;
  }

  /// Finds the files outside of Cargo's dep-info that also affect the build of
  /// the crate in [crateDirectory]: its `Cargo.toml`, `build.rs` and
  /// `rust-toolchain.toml`, and the nearest `Cargo.lock`.
  ///
  /// Cargo's dep-info only lists the crate's source files, so without these,
  /// changing a dependency, the build script or the toolchain would not
  /// re-run the build hook.
  Iterable<Uri> discoverCrateConfigurationFiles(String crateDirectory) {
    final directory = path.normalize(path.absolute(crateDirectory));
    final files = [
      for (final name in ['Cargo.toml', 'build.rs', 'rust-toolchain.toml'])
        path.join(directory, name),
    ];

    // NOTE: a crate in a Cargo workspace shares the workspace's Cargo.lock,
    // which is in an ancestor directory.
    for (var current = directory; ; current = path.dirname(current)) {
      final lockfile = path.join(current, 'Cargo.lock');
      if (File(lockfile).existsSync()) {
        files.add(lockfile);
        break;
      }
      if (path.dirname(current) == current) break;
    }

    final result = [
      for (final file in files)
        if (File(file).existsSync()) path.toUri(file),
    ];
    logger.fine('Discovered crate configuration files: $result');
    return result;
  }
}
