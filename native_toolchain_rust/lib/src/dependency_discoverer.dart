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
}
