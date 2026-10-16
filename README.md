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

## Numeric-expression subset

The root Zig module exposes an allocation-free evaluator:

```zig
pub fn evalNumberExpression(source: []const u8) error{InvalidSyntax, LimitExceeded}!Value
```

It supports decimal numbers, unary `+`/`-`, binary `+`, `-`, `*`, `/`,
parentheses, and space, tab, CR, and LF between tokens. Multiplication and
division precede addition and subtraction; binary operators associate left.
For example, `1 + 2 * 3` returns 7 and `(1 + 2) * 3` returns 9.

```text
exponent = [eE][+-]?[0-9]+
number = (0|[1-9][0-9]*)(\.[0-9]*)? exponent? | \.[0-9]+ exponent?
```

The entire input must match this subset. Leading zeros (`01`, `00.5`),
contiguous `++`, `--`, `**`, and all other syntax are rejected with
`InvalidSyntax`; `1 + +2` and `1 - -2` are valid. IEEE binary64 rounding,
signed zero, infinities, and subnormals are preserved; NaNs are canonicalized.
Inputs over 4096 bytes or more than 64 combined pending parentheses and unary
prefixes return `LimitExceeded` in every mode. Flat binary chains use loops.

Compare native runtime source evaluation against Node/V8 in each build mode:

```sh
node tests/expression-differential.mjs ReleaseFast
```

This check uses seed `0x4c4a5331`, generates 10,000 distinct valid expressions,
and reports total/distinct counts. Unsupported syntax is checked separately.

## Benchmarks

Run the primitive-operation benchmarks on Linux:

```sh
sh benchmarks/run.sh ReleaseFast
```
## License

[Apache License 2.0](LICENSE).

