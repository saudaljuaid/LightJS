// node tests/differential.mjs [Debug|ReleaseSafe|ReleaseFast|ReleaseSmall]
// ZIG selects the compiler; all build products live in the ignored cache.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

process.chdir(fileURLToPath(new URL('..', import.meta.url)));
const mode = process.argv[2] ?? 'Debug';
assert(['Debug', 'ReleaseSafe', 'ReleaseFast', 'ReleaseSmall'].includes(mode));
const zig = process.env.ZIG ?? 'zig';
const dir = resolve('.zig-cache', 'differential', mode);
mkdirSync(dir, { recursive: true });
function run(command, args, options = {}, expectedStatus = 0) {
  const result = spawnSync(command, args, { maxBuffer: 128 * 1024 * 1024, ...options });
  if (result.error) throw result.error;
  assert.equal(result.status, expectedStatus, `${command} ${args.join(' ')}\n${result.stderr}`);
  return result.stdout;
}
run(zig, ['build', `-Doptimize=${mode}`, '--prefix', dir]);
run(zig, ['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-O2',
  'tests/differential.c', `${dir}/lib/liblightjs.a`, '-Iinclude', '-o', `${dir}/native`]);
// Reject incomplete binary records, including tails after a complete record.
for (const completeBytes of [0, 16]) {
  for (let tailBytes = 1; tailBytes < 16; ++tailBytes) {
    run(`${dir}/native`, [], { input: Buffer.alloc(completeBytes + tailBytes) }, 1);
  }
}
run(zig, ['build-exe', 'src/root.zig', '-target', 'wasm32-freestanding',
  '-fno-entry', '-rdynamic', '-O', mode, `-femit-bin=${dir}/core.wasm`]);
const { instance: { exports: wasm } } = await WebAssembly.instantiate(readFileSync(`${dir}/core.wasm`));
const mask = (1n << 64n) - 1n;
const magnitudeMask = (1n << 63n) - 1n;
const inf = 0x7ff0000000000000n;
const nan = 0x7ff8000000000000n;
const tag = 0xfff8000000000000n;
const storage = new DataView(new ArrayBuffer(8));
function number(raw) {
  storage.setBigUint64(0, raw, true);
  return storage.getFloat64(0, true);
}
function bits(n) {
  if (Number.isNaN(n)) return nan;
  storage.setFloat64(0, n, true);
  return storage.getBigUint64(0, true);
}
function primitive(raw) {
  if (raw === tag) return { kind: 4n, value: undefined };
  if (raw === tag + 1n) return { kind: 3n, value: null };
  if (raw === tag + 2n) return { kind: 2n, value: false };
  if (raw === tag + 3n) return { kind: 2n, value: true };
  if ((raw & magnitudeMask) <= inf || raw === nan) return { kind: 1n, value: number(raw) };
  return null;
}
const edges = new Set([0n, 1n, 0x000fffffffffffffn, 0x0010000000000000n,
  0x7fefffffffffffffn, inf, inf + 1n, nan, nan + 1n, magnitudeMask,
  tag, tag + 1n, tag + 2n, tag + 3n, tag + 4n, mask]);
// Neighbors of every exponent boundary stress shifts, wrapping and rounding.
for (let exponent = 0n; exponent < 2048n; ++exponent) {
  const boundary = exponent << 52n;
  for (const delta of [-1n, 0n, 1n, 0x0008000000000000n, 0x000fffffffffffffn]) {
    const raw = (boundary + delta) & magnitudeMask;
    edges.add(raw);
    edges.add(raw | (1n << 63n));
  }
}
for (const n of [0.9, -0.9, 1.9, -1.9, 2147483647, 2147483648,
  -2147483649, 4294967295, 4294967296, 4294967297, -4294967297,
  2 ** 53, 2 ** 83, 2 ** 84, 1 + 2 ** -52, 1 + 2 ** -53]) edges.add(bits(n));
const seed = BigInt(process.env.DIFF_SEED ?? '0x4c696768744a5321');
assert(seed > 0n && seed <= mask);
let state = seed;
function random() {
  state ^= (state << 13n) & mask;
  state ^= state >> 7n;
  state ^= (state << 17n) & mask;
  return state & mask;
}
const pairs = [];
const special = [0n, 1n, 1n << 63n, nan, inf, inf | (1n << 63n), tag, tag + 1n,
  tag + 2n, tag + 3n, bits(1), bits(-1), bits(2), bits(0.5)];
for (const a of edges) {
  pairs.push([a, a], [a, random()]);
  for (const b of special) pairs.push([a, b]);
}
for (let i = 0; i < 100_000; ++i) pairs.push([random(), random()]);
for (const [x, y] of [[1, 2 ** -53], [1 + 2 ** -52, 2 ** -53],
  [2 ** 53, 1], [Number.MAX_VALUE, 2], [Number.MIN_VALUE, 2],
  [Number.MIN_VALUE, 0.5], [3 * Number.MIN_VALUE, 2], [1, 3],
  [2 ** -1022, 2], [2 ** -1022, 1 - 2 ** -52]]) {
  pairs.push([bits(x), bits(y)], [bits(-x), bits(y)]);
}
const input = Buffer.alloc(pairs.length * 16);
pairs.forEach(([a, b], i) => { input.writeBigUInt64LE(a, i * 16); input.writeBigUInt64LE(b, i * 16 + 8); });
// The native wire format is host endian; WebAssembly is always little endian.
assert.equal(new Uint8Array(new Uint16Array([1]).buffer)[0], 1, 'native runner requires a little-endian host');
const output = run(`${dir}/native`, [], { input });
const fields = ['number(a)', 'number(b)', 'kind', 'ToNumber', 'ToBoolean', 'ToInt32',
  'strictEqual', 'SameValue', 'SameValueZero', 'add', 'subtract', 'multiply', 'divide'];
assert.equal(output.length, pairs.length * fields.length * 8);
let comparisons = 0;
for (let i = 0; i < pairs.length; ++i) {
  const [a, b] = pairs[i];
  const x = number(a), y = number(b), p = primitive(a), q = primitive(b);
  const valid = p !== null && q !== null;
  const expected = [bits(x), bits(y), p?.kind ?? 0n, bits(p ? Number(p.value) : NaN),
    BigInt(p ? Boolean(p.value) : false), BigInt((p ? Number(p.value) >> 0 : 0) >>> 0),
    BigInt(valid && p.value === q.value), BigInt(valid && Object.is(p.value, q.value)),
    BigInt(valid && (p.value === q.value || (Number.isNaN(p.value) && Number.isNaN(q.value)))),
    bits(x + y), bits(x - y), bits(x * y), bits(x / y)];
  const actualWasm = [wasm.lightjs_number(x), wasm.lightjs_number(y), wasm.lightjs_kind(a),
    bits(wasm.lightjs_to_number(a)), wasm.lightjs_to_boolean(a),
    wasm.lightjs_to_int32(a) >>> 0, wasm.lightjs_strict_equal(a, b), wasm.lightjs_same_value(a, b),
    wasm.lightjs_same_value_zero(a, b), wasm.lightjs_number_add(x, y),
    wasm.lightjs_number_subtract(x, y), wasm.lightjs_number_multiply(x, y), wasm.lightjs_number_divide(x, y)];
  for (let j = 0; j < fields.length; ++j) {
    const context = `${mode} case ${i} ${fields[j]} a=${a.toString(16)} b=${b.toString(16)}`;
    assert.equal(output.readBigUInt64LE((i * fields.length + j) * 8), expected[j], `native ${context}`);
    assert.equal(BigInt.asUintN(64, BigInt(actualWasm[j])), expected[j], `wasm ${context}`);
    comparisons += 2;
  }
}
console.log(JSON.stringify({ mode, seed: `0x${seed.toString(16)}`, pairs: pairs.length,
  comparisons, node: process.versions.node, v8: process.versions.v8, zig: run(zig, ['version']).toString().trim() }));
