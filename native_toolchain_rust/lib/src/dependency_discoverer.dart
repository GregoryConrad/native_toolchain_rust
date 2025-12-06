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
        .expand((line) => line.trim().split(' ').skip(1))
        .followedBy([dependencyFilePath])
        .map(path.toUri);
  }
}
