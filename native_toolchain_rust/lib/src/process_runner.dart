import 'dart:io';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:native_toolchain_rust/src/exception.dart';
import 'package:path/path.dart' as path;

@internal
interface class ProcessRunner {
  const ProcessRunner(this.logger);
  final Logger logger;

  Future<String> invoke(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    try {
      logger.info(
        'Invoking "$executable $arguments" '
        '${workingDirectory != null ? 'in directory $workingDirectory ' : ''}'
        'with environment: ${environment ?? {}}',
      );
      final result = await Process.run(
        executable,
        arguments,
        environment: environment,
        workingDirectory: workingDirectory,
      );
      if (result.exitCode != 0) {
        throw RustProcessException(
          'Process finished with non-zero exit code: "$executable $arguments" '
          'with stdout: "${result.stdout}" and stderr: "${result.stderr}"',
        );
      }
      return result.stdout as String;
    } on ProcessException catch (exception, stackTrace) {
      logger.info(
        'Failed to invoke "$executable $arguments"',
        exception,
        stackTrace,
      );
      rethrow;
    }
  }
}

@internal
extension InvokeRustup on ProcessRunner {
  Future<String> invokeRustup(
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    late ProcessException lastException;
    for (final executable in _rustupExecutables) {
      try {
        return await invoke(
          executable,
          arguments,
          workingDirectory: workingDirectory,
          environment: environment,
        );
      } on ProcessException catch (e) {
        lastException = e;
      }
    }

    throw RustProcessException(
      'Failed to invoke rustup; is it installed? '
      'Checked the following paths: $_rustupExecutables. '
      'For help installing rust, see https://rustup.rs',
      inner: lastException,
    );
  }
}

/// `rustup` executables to attempt to launch, in order of preference
///
/// Defaults to `rustup` lookup via PATH, followed by `~/.cargo/bin/rustup`
List<String> get _rustupExecutables {
  final homeDirectory = Platform.isWindows
      ? Platform.environment['USERPROFILE']
      : Platform.environment['HOME'];

  return [
    'rustup',
    if (homeDirectory != null)
      path.join(homeDirectory, '.cargo', 'bin', 'rustup'),
  ];
}
