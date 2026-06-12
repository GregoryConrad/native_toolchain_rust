# Dart-Only Prebuilt Binaries Example

This example showcases [Prebuilt Binaries](../../README.md#prebuilt-binaries):
it is identical in spirit to the [dart_only](../dart_only) example,
except that its Rust binaries are also published to GitHub Releases
(via the [prebuilt-binaries workflow](../../.github/workflows/prebuilt-binaries.yml)),
so that consumers can opt in to downloading them instead of building from source.

## Trying It Out
Prebuilt binaries are opt-in:
without any extra configuration, running `dart test` in this directory
builds the Rust code from source (requiring rustup), just like the other examples.

To opt in to the prebuilt binaries instead, create a `native_toolchain_rust.toml`
in the root of *your* project.
Since this repository is a [pub workspace](https://dart.dev/tools/pub/workspaces),
the root project is the repository root, so create the file there:

```toml
[prebuilt-binaries.dart_only_prebuilt_binaries_example]
url = "https://github.com/GregoryConrad/native_toolchain_rust/releases/download/dart_only_prebuilt_binaries_example-v{version}/dart_only_prebuilt_binaries_example-{target}.bin"
```

Then, `dart test` will download the prebuilt binary for your machine
and skip the Rust build entirely (no rustup required!).

Note that `native_toolchain_rust.toml` is intentionally listed
in this repository's `.gitignore`:
since CI checkouts will never contain the file,
CI always builds (and tests) the Rust code from source.

## How the Binaries Are Published
The [prebuilt-binaries workflow](../../.github/workflows/prebuilt-binaries.yml)
builds the cdylib for a matrix of targets and uploads each one
as an asset of the `dart_only_prebuilt_binaries_example-v<version>` GitHub release,
where `<version>` is the `version` in this example's [pubspec.yaml](pubspec.yaml).
The asset names embed the Rust target triple,
matching the `{target}` placeholder in the URL template above.
