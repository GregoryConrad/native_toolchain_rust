import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await const RustBuilder(assetName: 'src/ffi.g.dart').run(
      input: input,
      output: output,
    );
  });
}
