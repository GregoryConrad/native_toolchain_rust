# 🧱 `native_toolchain_rust` 🦀

[![Build Status](https://github.com/GregoryConrad/native_toolchain_rust/actions/workflows/build.yml/badge.svg)](https://github.com/GregoryConrad/native_toolchain_rust/actions)
[![Github Stars](https://img.shields.io/github/stars/GregoryConrad/native_toolchain_rust.svg?style=flat&logo=github&colorB=deeppink&label=stars)](https://github.com/GregoryConrad/native_toolchain_rust)
[![MIT License](https://img.shields.io/badge/license-MIT-purple.svg)](https://opensource.org/licenses/MIT)

---

Rust support for Dart's [build hooks](https://dart.dev/tools/hooks).

## Why native_toolchain_rust?
1. It's opinionated.
   That might sound bad, but it's opinionated in the way that _keeps you from shooting yourself in the foot_.
2. Does more with less.
   The API is incredibly easy to use: the only thing you _need_ to provide is `assetName`,
   and the rest is auto-magically figured out.
   (But you can still tweak the functionality as much as you need to!)


## Getting Started
1. Install [rustup](https://rustup.rs), for Rust, on your development computer
   (if you are a library author, consumers of your package will have to do the same,
   unless they opt in to [Prebuilt Binaries](#prebuilt-binaries))
2. Run `flutter pub add native_toolchain_rust hooks` for Flutter or `dart pub add native_toolchain_rust hooks` for Dart-only
3. See [Code Setup](#code-setup)


## Code Setup
`native_toolchain_rust` will look (by default) for `native/` or `rust/` (customizable)
in your Dart package's root.
If you haven't already, create a `Cargo.toml` and `rust-toolchain.toml` in your chosen Rust directory;
keep reading for what these two files must contain
(but don't worry if you forget, you'll get a helpful error message).

### `hook/build.dart`
```dart
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    await RustBuilder(
      assetName: 'src/my_ffi_bindings.g.dart',
      // ...maybe enable some Cargo features or something in here too
    ).run(input: input, output: output);
  });
}
```

### `Cargo.toml`
Keep at least the following in your `Cargo.toml`.
```toml
[package]
name = "my-crate-name" # pick a name, doesn't matter

[lib]
crate-type = ["staticlib", "cdylib"] # THESE ARE IMPORTANT!
```

### `rust-toolchain.toml`
Keep at least the following in your `rust-toolchain.toml`.
```toml
[toolchain]
# WARNING: *do not* use `stable`, `beta`, or `nightly` (alone) for the channel!
# You must specify a version number/date in order to ensure reproducible builds.
channel = "1.90.0" # or newer. another example: `nightly-2025-01-01`

# The targets you want to support; these are the default:
targets = [
  # Android
  "armv7-linux-androideabi",
  "aarch64-linux-android",
  "x86_64-linux-android",

  # iOS (device + simulator)
  "aarch64-apple-ios",
  "aarch64-apple-ios-sim",
  "x86_64-apple-ios",

  # Windows
  "aarch64-pc-windows-msvc",
  "x86_64-pc-windows-msvc",

  # Linux
  "aarch64-unknown-linux-gnu",
  "x86_64-unknown-linux-gnu",

  # macOS
  "aarch64-apple-darwin",
  "x86_64-apple-darwin",
]
```


## Prebuilt Binaries
Normally, consumers of a package built with `native_toolchain_rust` need rustup installed
so the Rust code can be compiled from source on their machine.
As an alternative, application developers can *opt in* to downloading prebuilt binaries
on a per-package basis, which skips the Rust build entirely (no rustup required).

To opt in, create a `native_toolchain_rust.toml` file in the root of your project
(for [pub workspaces](https://dart.dev/tools/pub/workspaces), the workspace root):

```toml
[prebuilt-binaries.some_package_name]
url = "https://github.com/some-user/some-repo/releases/download/v{version}/my_crate-{target}.bin"
```

The `url` is a template for where to download the binary from,
and supports the following placeholders:

| Placeholder | Description | Example |
| --- | --- | --- |
| `{version}` | The version of the Dart package being built | `1.2.3` |
| `{target}` | The Rust target triple being built for | `aarch64-apple-darwin` |
| `{lib-name}` | The platform-specific dynamic library file name | `libmy_crate.so` |

Some notes:
- The downloaded binary must match the link mode of the build.
  It must be a `cdylib` for dynamic linking, which is what Dart/Flutter uses on all platforms as of now.
- The downloaded binary is saved locally under the correct platform-specific library name,
  so the remote file name in the URL template does not matter.
- Only ever download binaries from a source you trust!
  You are responsible for ensuring the binaries you download are safe
  and were built from the package's actual source code.

### Building From Source in CI
Add `native_toolchain_rust.toml` to your project's `.gitignore`:
since the file will then not exist in CI checkouts,
your CI will always build the Rust code from source,
while local development machines (with the file present) use the prebuilt binaries.

### Publishing Prebuilt Binaries via GitHub Releases
The URL template works great with GitHub release assets,
which are downloadable (for public repositories) without any authentication:
```
https://github.com/<owner>/<repo>/releases/download/<tag>/<asset-name>
```

For example, package authors can attach a binary per target triple to each release
in a GitHub Actions workflow:
```yaml
jobs:
  upload-prebuilt-binaries:
    strategy:
      matrix:
        include:
          - os: macos-latest
            target: aarch64-apple-darwin
            binary: libmy_crate.dylib
          - os: ubuntu-latest
            target: x86_64-unknown-linux-gnu
            binary: libmy_crate.so
          - os: windows-latest
            target: x86_64-pc-windows-msvc
            binary: my_crate.dll
          # ...and any other targets you wish to support
    runs-on: ${{ matrix.os }}
    defaults:
      run:
        shell: bash
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v5
      - run: rustup target add ${{ matrix.target }}
        working-directory: rust
      - run: cargo build --release --target ${{ matrix.target }}
        working-directory: rust
      # NOTE: release asset download URLs use the uploaded *file* name,
      # so rename the binary to its target-specific asset name before uploading.
      - run: cp "rust/target/${{ matrix.target }}/release/${{ matrix.binary }}" "my_crate-${{ matrix.target }}.bin"
      - run: gh release upload ${{ github.ref_name }} "my_crate-${{ matrix.target }}.bin"
        env:
          GH_TOKEN: ${{ github.token }}
```

Downstream users can then consume those binaries with the URL template from above:
```toml
[prebuilt-binaries.some_package_name]
url = "https://github.com/some-user/some-repo/releases/download/v{version}/my_crate-{target}.bin"
```

