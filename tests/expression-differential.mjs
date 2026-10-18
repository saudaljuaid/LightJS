// node tests/expression-differential.mjs [Debug|ReleaseSafe|ReleaseFast|ReleaseSmall] [comparison|program]
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

process.chdir(fileURLToPath(new URL('..', import.meta.url)));
const mode = process.argv[2] ?? 'Debug';
assert(['Debug', 'ReleaseSafe', 'ReleaseFast', 'ReleaseSmall'].includes(mode));
const comparison = process.argv[3] === 'comparison';
const program = process.argv[3] === 'program';
assert(process.argv[3] === undefined || comparison || program);
const zig = process.env.ZIG ?? 'zig';
const dir = resolve('.zig-cache', 'expression-differential', mode + (program ? '-program' : comparison ? '-comparison' : ''));
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
  `-Mroot=tests/${program ? 'program' : comparison ? 'comparison' : 'expression'}-bridge.zig`, '-O', mode,
  '-Mlightjs=src/root.zig', `-femit-bin=${native}`]);
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
  const format = program ? /^(?:[0-9a-f]{16}|InvalidSyntax|UnknownIdentifier|DuplicateBinding|LimitExceeded)$/ : comparison ? /^(?:fff800000000000[23]|InvalidSyntax|LimitExceeded)$/ :
    /^(?:[0-9a-f]{16}|InvalidSyntax|LimitExceeded)$/;
  for (const line of lines) assert.match(line, format);
  return lines;
}
// Incomplete frames, overlarge protocol lengths and tails must fail the process.
for (const input of [Buffer.from([1]), Buffer.from([1, 0, 0]),
  Buffer.from([1, 0, 0, 0]), Buffer.from([2, 0, 0, 0, 49]),
  Buffer.from([2, 16, 0, 0]), Buffer.concat([frame('1'), Buffer.from([0])])]) {
  run(native, [], { input }, 1);
}
const seed = program ? 0x4c4a5031 : comparison ? 0x4c4a4331 : 0x4c4a5331;
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
const oracles = new Map();
function programSource(statements, final, ending = '') {
  const source = statements + final + ending;
  oracles.set(source, `"use strict";${statements}return (${final});`);
  return source;
}
function programExpression(depth, names) {
  if (depth === 0 || random(4) === 0) return names.length && random(2) === 0 ? pick(names) : literal();
  if (random(4) === 0) return `${pick(['+', '-'])}${whitespace()}${programExpression(depth - 1, names)}`;
  return `(${programExpression(depth - 1, names)}${whitespace()}${pick(['+', '-', '*', '/'])}${whitespace()}${programExpression(depth - 1, names)})`;
}
function generateProgram() {
  const names = [];
  let statements = '';
  const count = 1 + random(7);
  for (let i = 0; i < count; i++) {
    const declare = names.length === 0 || random(2) === 0;
    const name = declare ? pick(['x', 'X', 'letter', 'let0', '$', '_', 'price']) + names.length : pick(names);
    const rhs = programExpression(2, names);
    statements += `${declare ? `let${whitespace()}` : ''}${name}${whitespace()}=${whitespace()}${rhs};${whitespace()}`;
    if (declare) names.push(name);
  }
  return programSource(statements, programExpression(3, names), pick(['', ';', '; \n']));
}
const generated = new Set();
const operators = ['<', '<=', '>', '>=', '===', '!=='];
while (generated.size < 10_000) generated.add(program ? generateProgram() : comparison ?
  `${expression(4)}${whitespace()}${pick(operators)}${whitespace()}${expression(4)}` : expression(4));
let sources = [...generated, ...literals, '1 + 2 * 3', '(1 + 2) * 3', '8 / 4 / 2', '8 - 4 - 2',
  '-0', '-(0)', '1 / -0', '0 / 0', '-0 + -0', '0 + -0', '-0 - 0', '0 * -1',
  '-0 / 1', '- - - 0', '1 + +2', '1 - -2'];
if (comparison) sources = [...generated, ...literals.flatMap(value =>
  operators.map(op => `${value} ${op} ${value}`)), ...operators.flatMap(op =>
  ['-0', '0 / 0', '1 / 0', '-1 / 0', '5e-324', '9007199254740993'].map(value => `${value} ${op} 0`)),
  '1 + 2 * 3 < 2 * 4 + 1', '(1 + 2) < (3 * 4)', '(1 + 2) * 3 >= 9',
  '0 / 0 !== 0 / 0', '9007199254740993 === 9007199254740992'];
if (program) sources = [...generated, ...literals.map(value => programSource(`let x = ${value};`, 'x')),
  ...[['', '1 + 2 * 3'], ['let x=2; let y=x*3; x=x+1;', 'x+y'],
    ['let price=12; let quantity=3; price=price+2;', 'price*quantity'],
    ['let x=1; x=x+1; x=x*3; x=x-1; x=x/2;', 'x'],
    ['let letter=2; let let0=3; let $=4; let _=5;', 'letter+let0+$+_'],
    ['let x=2; let X=3;', '(x+X)*-2'], ['let zero=-0;', '1/zero'],
    ['let zero=-0;', 'zero'], ['let x=0/0;', 'x'], ['let x=1/0;', '-x'],
    ['let x=5e-324;', 'x/2'], ['let x=-0; x=x*-1;', 'x']]
    .map(([statements, final], i) => programSource(statements, final, i % 2 ? '; \t\n' : ''))];
const storage = new DataView(new ArrayBuffer(8));
function bits(number) {
  if (Number.isNaN(number)) return '7ff8000000000000';
  storage.setFloat64(0, number);
  return storage.getBigUint64(0).toString(16).padStart(16, '0');
}
const actual = evaluate(sources);
sources.forEach((source, i) => {
  const value = Function(program ? oracles.get(source) : `"use strict"; return (${source});`)();
  if (program) assert.equal(typeof value, 'number');
  if (comparison) assert.equal(typeof value, 'boolean');
  const expected = comparison ? (value ? 'fff8000000000003' : 'fff8000000000002') : bits(value);
  assert.equal(actual[i], expected, `${mode} case ${i}: ${JSON.stringify(source)}`);
});
// V8 accepts some unsupported syntax; these are checked only against our subset.
let invalid = ['', ' ', '01', '00.5', '1++2', '1--2', '1**2', '++1', '--1', '1 +++2',
  '1 + --2', '1/*x*/+2', '1//x', '0x10', '1n', '1_0', 'Infinity', 'NaN', 'a', '"1"',
  '1;', '1,2', '1%2', '1 2', '1\0', '1\v', '1\f', '1\u00a0', '.', '.e1', '1e', '1e+',
  '1..0', '(1', '1)', '()', '1+', '1e2e3', '0b1', '0o1', '1\u0080'];
if (comparison) invalid = [...invalid.map(value => `${value} < 2`), '', '1', '1 <', '< 1',
  '1 < 2 < 3', '1 === 1 === 1', '(1 < 2)', '(1 < 2) === 1', 'true < 1', '1 === false',
  '1 == 1', '1 != 2', '1 = 2', '1 && 2', '1 || 2', '1 < = 2', '1 > = 2', '1 = == 2',
  '1 ! == 2', '1 ==== 2', '1 !=== 2', '1 << 2', '1 >> 2', '1 < 2;', '1 < 2 junk',
  '1 < 2\0', '1 < 2\v', '1 < 2, 3', '1 < (2 > 1)', '1 < 2 +'];
if (program) invalid = ['', ' ', 'let x=1;', 'let x=1', 'let x=1 x', 'let x=1; x; x',
  'let x=1; x;;', 'let x=1; x=2;', '1;1', 'let x=1; x+=1; x', 'let x=1; ++x',
  'let x=1; x++', 'let x=1; (x=2)', 'let x=1; x<2', 'let x=1; x===1',
  'let x=1; x()', 'let x=1; {x}', 'let x=1; x/*c*/', 'let x=1; x//c',
  'let x=1; true', 'let x=1; "x"', 'const x=1; x', 'var x=1; x', 'let x=01; x',
  'let x=1, y=2; x', 'let x=1; x=; x', 'let x=1; x\0', 'let x=1; x\v',
  ...('await break case catch class const continue debugger default delete do else enum export extends false finally for function if import in instanceof let new null return super switch this throw true try typeof var void while with yield implements interface package private protected public static eval arguments')
    .split(' ').map(name => `let ${name}=1; 1`)];
assert.deepEqual(evaluate(invalid), invalid.map(() => 'InvalidSyntax'));
const expectedErrors = program ? [
  ...['x', 'x=1; 1', 'let x=x; x', 'let x=1; y', 'let x=1; y=2; x',
    'NaN', 'Infinity', 'undefined', 'let x=1; X'].map(source => [source, 'UnknownIdentifier']),
  ...['let x=1; let x=2; x', 'let $=0; let $=1; $'].map(source => [source, 'DuplicateBinding'])] : [];
if (program) assert.deepEqual(evaluate(expectedErrors.map(([source]) => source)), expectedErrors.map(([, error]) => error));
const boundary = comparison ? '1<2' : '1';
assert.deepEqual(evaluate([4096, 4097].map(length => ' '.repeat(length - boundary.length) + boundary)),
  [comparison ? 'fff8000000000003' : '3ff0000000000000', 'LimitExceeded']);
console.log(JSON.stringify({ mode, comparison, ...(program ? { program, expectedErrors: expectedErrors.length } : {}), seed: `0x${seed.toString(16)}`, generated: generated.size,
  total: sources.length, distinct: new Set(sources).size, invalid: invalid.length,
  node: process.versions.node, v8: process.versions.v8, zig: run(zig, ['version']).toString().trim() }));
