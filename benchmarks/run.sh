#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
zig=${ZIG:-zig}
mode=${1:-ReleaseFast}
cpu=${CPU:-baseline}
out=zig-out/benchmarks/$mode-$cpu
mkdir -p "$out"
"$zig" build-lib src/root.zig -O "$mode" -mcpu "$cpu" -fllvm -fPIC \
    -fcompiler-rt -femit-bin="$out/liblightjs.a" -femit-asm="$out/lightjs.s"
"$zig" build-exe -O "$mode" -mcpu "$cpu" -fllvm -fno-lto --dep value \
    -Mroot=benchmarks/value.zig -O "$mode" -mcpu "$cpu" -Mvalue=src/value.zig \
    "$out/liblightjs.a" -lc -femit-bin="$out/value" -femit-asm="$out/value.s"
printf 'Flags: -O %s -mcpu %s -fllvm -fno-lto; separately linked Zig C ABI\n' "$mode" "$cpu"
if [ -n "${BENCH_CPU:-}" ]; then
    exec taskset -c "$BENCH_CPU" "$out/value"
fi
exec "$out/value"
