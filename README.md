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

## Numeric-comparison subset

The root Zig module also exposes an allocation-free evaluator returning a
canonical boolean `Value`:

```zig
pub fn evalNumberComparison(source: []const u8) error{InvalidSyntax, LimitExceeded}!Value
```

```text
comparison = numeric_expression comparison_operator numeric_expression
comparison_operator = "<" | "<=" | ">" | ">=" | "===" | "!=="
numeric_expression = product (("+" | "-") product)*
product = prefix (("*" | "/") prefix)*
prefix = ("+" | "-") prefix | "(" numeric_expression ")" | number
```

`number` follows the decimal grammar above. Space, tab, CR, and LF may separate
tokens; comparison operator characters must be contiguous. The existing
rejection of contiguous `++`, `--`, and `**` applies. The entire input must
contain exactly one comparison. Numeric parentheses are supported; comparison
chains, comparisons inside parentheses, boolean operands, `==`, `!=`, assignment,
logical operators, and all other syntax return `InvalidSyntax`.

Examples: `1 + 2 < 4`, `(1 + 2) * 3 >= 9`, `(1 + 2) < (3 * 4)`,
`-0 === 0`, and `0 / 0 !== 0 / 0` all return true. Ordered comparisons with
NaN return false; strict equality equates signed zeros and never equates NaNs.
Strict inequality negates strict equality. Numeric rounding, infinity,
subnormal behavior, and the 4096-byte / 64-pending-level limits are unchanged.

Run the native runtime-source comparison differential check in each build mode:

```sh
node tests/expression-differential.mjs ReleaseFast comparison
```

It uses seed `0x4c4a4331`, generates 10,000 distinct valid comparisons, reports
generated/total/distinct counts, and checks unsupported syntax separately.

## Numeric-program subset

The root Zig module adds an allocation-free evaluator returning the final
expression as a canonical Number `Value`:

```zig
pub fn evalNumberProgram(source: []const u8) error{InvalidSyntax, UnknownIdentifier, DuplicateBinding, LimitExceeded}!Value
```

```text
program = (declaration | assignment)* numeric_expression ";"?
declaration = "let" identifier "=" numeric_expression ";"
assignment = identifier "=" numeric_expression ";"
identifier = [A-Za-z_$][A-Za-z0-9_$]*
```

Numeric expressions reuse the arithmetic grammar above, with identifiers also
accepted as prefix operands. Whitespace remains space, tab, CR, and LF. This is
a bounded numeric-program subset with a required final expression. Declarations
and assignments require semicolons; only whitespace may follow the final one.
Bindings are case-sensitive and local to each call. Initializers run before
installing bindings; reassignment may read the previous value. No names are
predefined, including `NaN`, `Infinity`, and `undefined`.

Reserved identifiers are `await break case catch class const continue debugger
default delete do else enum export extends false finally for function if import
in instanceof let new null return super switch this throw true try typeof var
void while with yield implements interface package private protected public
static eval arguments`. Unsupported syntax returns `InvalidSyntax`, unknown
reads/assignment targets return `UnknownIdentifier`, and duplicate declarations
return `DuplicateBinding`. Comparisons, boolean/string operands, other declaration
forms, blocks, calls, functions, comments, and assignment expressions are excluded.

Examples: `let x=2; let y=x*3; x=x+1; x+y` returns 9;
`let price=12; let quantity=3; price=price+2; price*quantity;` returns 42;
`let zero=-0; 1/zero` returns negative infinity. IEEE behavior is unchanged.
The fixed table allows 64 bindings; reassignment uses no new slot. A 65th
binding, input over 4096 bytes, or more than 64 combined pending unary/parenthesis
levels returns `LimitExceeded`. Each initializer, RHS, and final expression starts
at depth zero. Statements and flat arithmetic chains are processed iteratively.

Run `node tests/expression-differential.mjs ReleaseFast program` in each mode.
Seed `0x4c4a5031` generates 10,000 distinct programs, pairing statements and final
expressions with an explicit strict Node/V8 return. Complete source reaches the
compiled native evaluator at runtime; unsupported syntax/errors are checked separately.

## Benchmarks

Run the primitive-operation benchmarks on Linux:

```sh
sh benchmarks/run.sh ReleaseFast
```
## License

[Apache License 2.0](LICENSE).

