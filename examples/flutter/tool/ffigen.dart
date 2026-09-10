import 'dart:io';

import 'package:ffigen/ffigen.dart';

Future<void> main() async {
  final packageRoot = Platform.script.resolve('../');
  await FfiGenerator(
    input: Input(entryPoints: [packageRoot.resolve('rust/bindings.h')]),
    output: Output(
      dart: DartOutput(path: packageRoot.resolve('lib/src/ffi.g.dart')),
    ),
    visitors: [
      Visitor(
        func: (node) {
          const toInclude = {'reset_count', 'increase_count', 'get_count'};
          node.isIncluded = toInclude.contains(node.originalName);
        },
      ),
    ],
  ).generate();
}
