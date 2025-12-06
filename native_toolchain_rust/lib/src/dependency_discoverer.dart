import 'dart:io';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

@internal
interface class DependencyDiscoverer {
  const DependencyDiscoverer(this.logger);

  final Logger logger;

  /// Finds all the dependencies from the specified dependency file,
  /// including the dependency file itself.
  Iterable<Uri> discover(String dependencyFilePath) {
    logger.fine('Discovering dependencies in $dependencyFilePath');
    return File(dependencyFilePath)
        .readAsLinesSync()
        .map((line) {
          final splitIndex = line.indexOf(':');
          if (splitIndex < 0) return null;
          return line.substring(splitIndex + 1).trim();
        })
        .nonNulls
        .expand((files) => files.split(' '))
        .followedBy([dependencyFilePath])
        .map(path.toUri);
  }
}
