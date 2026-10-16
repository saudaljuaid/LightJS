// node tests/expression-differential.mjs [Debug|ReleaseSafe|ReleaseFast|ReleaseSmall]
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

process.chdir(fileURLToPath(new URL('..', import.meta.url)));
const mode = process.argv[2] ?? 'Debug';
assert(['Debug', 'ReleaseSafe', 'ReleaseFast', 'ReleaseSmall'].includes(mode));
const zig = process.env.ZIG ?? 'zig';
const dir = resolve('.zig-cache', 'expression-differential', mode);
mkdirSync(dir, { recursive: true });
function run(command, args, options = {}, status = 0) {
  const result = spawnSync(command, args, { maxBuffer: 32 * 1024 * 1024, ...options });
  if (result.error) throw result.error;
  assert.equal(result.signal, null, `${command} terminated by signal`);
  assert.equal(result.status, status, `${command} ${args.join(' ')}\n${result.stderr}`);
  return result.stdout;
}
const native = `${dir}/native`;
run(zig, ['build-exe', '-lc', '-O', mode, '--dep', 'lightjs',
  '-Mroot=tests/expression-bridge.zig', '-O', mode, '-Mlightjs=src/root.zig', `-femit-bin=${native}`]);
function frame(source) {
  const bytes = Buffer.from(source);
  const header = Buffer.alloc(4);
  header.writeUInt32LE(bytes.length);
  return Buffer.concat([header, bytes]);
}
function evaluate(sources) {
  const output = run(native, [], { input: Buffer.concat(sources.map(frame)) }).toString('utf8');
  const lines = output.split('\n');
  assert.equal(lines.pop(), '', 'missing final newline');
  assert.equal(lines.length, sources.length, 'native output count');
  for (const line of lines) assert.match(line, /^(?:[0-9a-f]{16}|InvalidSyntax|LimitExceeded)$/);
  return lines;
}
// Incomplete frames, overlarge protocol lengths and tails must fail the process.
for (const input of [Buffer.from([1]), Buffer.from([1, 0, 0]),
  Buffer.from([1, 0, 0, 0]), Buffer.from([2, 0, 0, 0, 49]),
  Buffer.from([2, 16, 0, 0]), Buffer.concat([frame('1'), Buffer.from([0])])]) {
  run(native, [], { input }, 1);
}
const seed = 0x4c4a5331;
let state = seed;
function random(n) {
  state ^= state << 13;
  state ^= state >>> 17;
  state ^= state << 5;
  return (state >>> 0) % n;
}
const pick = values => values[random(values.length)];
const whitespace = () => pick([' ', '\t', '\r', '\n', ' \t']);
const literals = ['0', '.5', '1.', '9007199254740993', '1.00000000000000011102230246251565404236316680908203125',
  '1.00000000000000033306690738754696212708950042724609375', '1.7976931348623157e308',
  '1.7976931348623159e308', '2.2250738585072014e-308', '4.9406564584124654e-324',
  '2.4703282292062327e-324', '2.4703282292062328e-324', '1e9999', '1e-9999'];
function literal() {
  if (random(3) === 0) return pick(literals);
  const digits = String(random(1_000_000_000));
  return pick([digits, `${digits}.`, `.${digits}`, `${digits}.${random(1_000_000)}`]) +
    pick(['', `e+${random(330)}`, `E-${random(330)}`]);
}
function expression(depth) {
  if (depth === 0 || random(4) === 0) return literal();
  if (random(4) === 0) return `${pick(['+', '-'])}${whitespace()}${expression(depth - 1)}`;
  return `(${expression(depth - 1)}${whitespace()}${pick(['+', '-', '*', '/'])}${whitespace()}${expression(depth - 1)})`;
}
const generated = new Set();
while (generated.size < 10_000) generated.add(expression(4));
const sources = [...generated, ...literals, '1 + 2 * 3', '(1 + 2) * 3', '8 / 4 / 2', '8 - 4 - 2',
  '-0', '-(0)', '1 / -0', '0 / 0', '-0 + -0', '0 + -0', '-0 - 0', '0 * -1',
  '-0 / 1', '- - - 0', '1 + +2', '1 - -2'];
const storage = new DataView(new ArrayBuffer(8));
function bits(number) {
  if (Number.isNaN(number)) return '7ff8000000000000';
  storage.setFloat64(0, number);
  return storage.getBigUint64(0).toString(16).padStart(16, '0');
}
const actual = evaluate(sources);
sources.forEach((source, i) => {
  const expected = bits(Function(`"use strict"; return (${source});`)());
  assert.equal(actual[i], expected, `${mode} case ${i}: ${JSON.stringify(source)}`);
});
// V8 accepts some unsupported syntax; these are checked only against our subset.
const invalid = ['', ' ', '01', '00.5', '1++2', '1--2', '1**2', '++1', '--1', '1 +++2',
  '1 + --2', '1/*x*/+2', '1//x', '0x10', '1n', '1_0', 'Infinity', 'NaN', 'a', '"1"',
  '1;', '1,2', '1%2', '1 2', '1\0', '1\v', '1\f', '1\u00a0', '.', '.e1', '1e', '1e+',
  '1..0', '(1', '1)', '()', '1+', '1e2e3', '0b1', '0o1', '1\u0080'];
assert.deepEqual(evaluate(invalid), invalid.map(() => 'InvalidSyntax'));
assert.deepEqual(evaluate([' '.repeat(4095) + '1', ' '.repeat(4096) + '1']),
  ['3ff0000000000000', 'LimitExceeded']);
console.log(JSON.stringify({ mode, seed: `0x${seed.toString(16)}`, generated: generated.size,
  total: sources.length, distinct: new Set(sources).size, invalid: invalid.length,
  node: process.versions.node, v8: process.versions.v8, zig: run(zig, ['version']).toString().trim() }));
