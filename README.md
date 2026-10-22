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
   (if you are a library author, consumers of your package will have to do the same)
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

## Android 16 KB page sizes
On the 64 bit Android targets (`aarch64-linux-android` and `x86_64-linux-android`),
your library is linked with `-Wl,-z,max-page-size=16384`
so that it supports 16 KB page sizes, which
[Google Play requires](https://developer.android.com/guide/practices/page-sizes)
for apps targeting Android 15 or later.
NDK r28 and newer already do this by default, but older NDKs align on 4 KB.
The flag is added by a small wrapper around the NDK's `clang`,
so your own `rustflags` are left untouched;
if you need a different page size, pass it yourself
(e.g., `-C link-arg=-Wl,-z,max-page-size=4096`) and yours will take precedence.
