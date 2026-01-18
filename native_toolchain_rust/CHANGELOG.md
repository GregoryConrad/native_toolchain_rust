## 1.0.3

 - **FIX**: use proper file extension for Android NDK ranlib on Windows ([#52](https://github.com/GregoryConrad/native_toolchain_rust/issues/52)).
 - **FIX**: fix `<target-triple>-ranlib` command not found ([#50](https://github.com/GregoryConrad/native_toolchain_rust/issues/50)).

## 1.0.2

 - **FIX**: pass in no extra flag for debug mode ([#47](https://github.com/GregoryConrad/native_toolchain_rust/issues/47)).

## 1.0.1

 - **FIX**: improve colon handling in dependency discovery for windows ([#45](https://github.com/GregoryConrad/native_toolchain_rust/issues/45)).
 - **FIX**: add all build dependencies to the output for rebuilds ([#44](https://github.com/GregoryConrad/native_toolchain_rust/issues/44)).

## 1.0.0

 - Rebrand to native_toolchain_rust from native_toolchain_rs

 - **DOCS**: update outdated "native assets" terminology.

## 1.0.0

 - Bump "native_toolchain_rs" to `1.0.0`.

## 0.1.2+4

 - Bump dependencies

## 0.1.2+3

 - **FIX**: set more NDK env vars + update examples ([#27](https://github.com/GregoryConrad/native_toolchain_rs/issues/27)).

## 0.1.2+2

 - **FIX**: use the .cmd NDK clangs on Windows ([#24](https://github.com/GregoryConrad/native_toolchain_rs/issues/24)).

## 0.1.2+1

 - **FIX**: drop .exe from NDK binaries and fix NDK target triples ([#22](https://github.com/GregoryConrad/native_toolchain_rs/issues/22)).

## 0.1.2

 - **FEAT**: add a default logger ([#20](https://github.com/GregoryConrad/native_toolchain_rs/issues/20)).
 - **FEAT**: make RustBuilder implement Builder interface ([#19](https://github.com/GregoryConrad/native_toolchain_rs/issues/19)).

## 0.1.1+3

 - **FIX**: revert to test 1.26.2 for stable flutter.

## 0.1.1+2

 - **FIX**: revert to meta 1.16 for stable flutter.

## 0.1.1+1

 - **REFACTOR**: switch to monorepo ([#15](https://github.com/GregoryConrad/native_toolchain_rs/issues/15)).
 - **FIX**: ensure toolchain is downloaded when logger is null.
 - **FIX**: use corrected library file name.
 - **DOCS**: move lingering example dir to actual package.

## 0.1.1

 - **FIX**: throw RustValidationException on bad toolchain, add unit tests ([#11](https://github.com/GregoryConrad/native_toolchain_rs/issues/11)).
 - **FEAT**: improve exception help messages ([#12](https://github.com/GregoryConrad/native_toolchain_rs/issues/12)).
 - **FEAT**: add exceptions to the public API ([#8](https://github.com/GregoryConrad/native_toolchain_rs/issues/8)).
 - **DOCS**: add reference to (WIP) examples directory ([#14](https://github.com/GregoryConrad/native_toolchain_rs/issues/14)).
 - **DOCS**: update package description ([#13](https://github.com/GregoryConrad/native_toolchain_rs/issues/13)).
 - **DOCS**: improve/clarify README ([#10](https://github.com/GregoryConrad/native_toolchain_rs/issues/10)).

## 0.1.0

> Note: This release has breaking changes.

 - **BREAKING** **FEAT**: add working implementation.
