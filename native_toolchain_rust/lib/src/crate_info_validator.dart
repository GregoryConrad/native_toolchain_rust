import 'package:meta/meta.dart';
import 'package:native_toolchain_rust/src/exception.dart';
import 'package:native_toolchain_rust/src/toml_parsing.dart';

@internal
interface class CrateInfoValidator {
  const CrateInfoValidator({
    required this.toolchainTomlParser,
    required this.cargoManifestParser,
  });

  final ToolchainTomlParser toolchainTomlParser;
  final CargoManifestParser cargoManifestParser;

  ({String? libName, String crateName, String toolchainChannel})
  fetchAndValidateCrateInfo({
    required String manifestPath,
    required String toolchainTomlPath,
    required String targetTriple,
  }) {
    final manifest = cargoManifestParser.parseManifest(
      manifestPath,
    );

    final [
      String? libName,
      String crateName,
      String toolchainChannel,
    ] = RustValidationException.compose<dynamic>([
      () => manifest.libName,
      () {
        final CargoManifest(
          :libName,
          :crateName,
          :libCrateTypes,
        ) = cargoManifestParser.parseManifest(
          manifestPath,
        );

        const requiredTypes = ['staticlib', 'cdylib'];
        if (!requiredTypes.every(libCrateTypes.contains)) {
          throw RustValidationException([
            '''
Your Cargo.toml must specify $requiredTypes under `lib.crate-types`.
For more information, see https://github.com/GregoryConrad/native_toolchain_rust?tab=readme-ov-file#cargotoml''',
          ]);
        }

        return crateName;
      },
      () {
        final (:channel, :targets) = toolchainTomlParser.parseToolchainToml(
          toolchainTomlPath,
        );

        final toolchainIssues = <String>[];

        const deniedChannels = {'stable', 'beta', 'nightly'};
        if (deniedChannels.contains(channel)) {
          toolchainIssues.add(
            '''
The rust-toolchain.toml is using the `$channel` channel, which is not allowed.
Please specify an exact version (e.g., `1.90.0`) to ensure a reproducible build.
For more information, see https://github.com/GregoryConrad/native_toolchain_rust?tab=readme-ov-file#rust-toolchaintoml''',
          );
        }

        if (!targets.contains(targetTriple)) {
          toolchainIssues.add(
            '''
The rust-toolchain.toml does not include the target `$targetTriple`.
If you wish to support this target, please add it to the `targets` array in the rust-toolchain.toml file.
For more information, see https://github.com/GregoryConrad/native_toolchain_rust?tab=readme-ov-file#rust-toolchaintoml''',
          );
        }

        if (toolchainIssues.isNotEmpty) {
          throw RustValidationException(toolchainIssues);
        }

        return channel;
      },
    ]);

    return (
      libName: libName,
      crateName: crateName,
      toolchainChannel: toolchainChannel,
    );
  }
}
