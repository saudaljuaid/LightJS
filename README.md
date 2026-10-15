<p align="center">
  <img src="https://github.com/user-attachments/assets/bff09302-01f4-4d7d-b2fe-f0c091f63541" alt="LightJS logo" width="120">
</p>

# LightJS

A JavaScript engine in early development, focused on speed and reliability.

## Build

Requires Zig **0.17.0**.

```sh
zig build
```
## Test

Run the Zig, C, and Rust checks:

```sh
zig build test test-rust
```

The Rust checks require a compiler supporting Rust edition 2024.

Run all four Zig build modes:

```sh
for mode in Debug ReleaseSafe ReleaseFast ReleaseSmall; do
  zig build test test-rust -Doptimize="$mode"
done
```

With Node.js installed, compare native and WebAssembly primitive operations against V8:

```sh
node tests/differential.mjs ReleaseFast
```

## Benchmarks

Run the primitive-operation benchmarks on Linux:

```sh
sh benchmarks/run.sh ReleaseFast
```
## License

[Apache License 2.0](LICENSE).

