import 'dart:io';

import 'package:meta/meta.dart';

/// An [Exception] representing a failure while trying to build Rust assets.
sealed class RustBuildException implements Exception {}

/// A [RustBuildException] that specifies there were some issues
/// while validating the project.
///
/// # WARNING
/// This is experimental!
/// It may change on any new release without notice!
/// Please file an issue with your use-case for it, if you do use it.
@experimental
final class RustValidationException implements RustBuildException {
  /// Creates a [RustValidationException] with [validationErrors].
  const RustValidationException(this.validationErrors);

  /// The validation issues encountered.
  final List<String> validationErrors;

  /// Calls all [functions] and throws an aggregate [RustValidationException]
  /// if any function in [functions] threw.
  /// Otherwise, returns the [functions]' results.
  static List<T> compose<T>(Iterable<T Function()> functions) {
    final response = <T>[];
    final validationErrors = <String>[];

    for (final function in functions) {
      try {
        response.add(function());
      } on RustValidationException catch (e) {
        validationErrors.addAll(e.validationErrors);
      }
    }

    if (validationErrors.isNotEmpty) {
      throw RustValidationException(validationErrors);
    }

    return response;
  }

  @override
  String toString() =>
      '''
RustValidationException(
${validationErrors.map((e) => '  - $e').join(Platform.lineTerminator)}
)''';
}

/// A [RustBuildException] that specifies there was an issue
/// when invoking an external process.
///
/// # WARNING
/// This is experimental!
/// It may change on any new release without notice!
/// Please file an issue with your use-case for it, if you do use it.
@experimental
final class RustProcessException implements RustBuildException {
  /// Creates a [RustProcessException] with [message] and [inner].
  const RustProcessException(this.message, {this.inner});

  /// The message associated with this [RustProcessException].
  final String message;

  /// The inner [ProcessException],
  /// in case this [RustProcessException] is wrapping around one.
  final ProcessException? inner;

  @override
  String toString() =>
      'RustProcessException('
      'message: $message, '
      'innerProcessException: ${inner ?? 'none'}'
      ')';
}

/// A [RustBuildException] that specifies there was an issue
/// while downloading a prebuilt binary.
final class RustPrebuiltBinaryException implements RustBuildException {
  /// Creates a [RustPrebuiltBinaryException] with [message].
  const RustPrebuiltBinaryException(this.message);

  /// The message associated with this [RustPrebuiltBinaryException].
  final String message;

  @override
  String toString() => 'RustPrebuiltBinaryException(message: $message)';
}

// NOTE: this is here so that end-users can't exhaustively pattern match
// (and thus gives us some API flexibility for new types)
// ignore: unused_element
final class _NoBreakingChangeForNewExceptions implements RustBuildException {}
