const std = @import("std");
const builtin = @import("builtin");
const Value = @import("value").Value;

extern "c" fn lightjs_number(f64) u64;
extern "c" fn lightjs_boolean(u32) u64;
extern "c" fn lightjs_kind(u64) u32;
extern "c" fn lightjs_to_number(u64) f64;
extern "c" fn lightjs_to_boolean(u64) u32;
extern "c" fn lightjs_to_int32(u64) i32;
extern "c" fn lightjs_strict_equal(u64, u64) u32;
extern "c" fn lightjs_same_value(u64, u64) u32;
extern "c" fn lightjs_same_value_zero(u64, u64) u32;
extern "c" fn lightjs_number_add(f64, f64) u64;
extern "c" fn lightjs_number_subtract(f64, f64) u64;
extern "c" fn lightjs_number_multiply(f64, f64) u64;
extern "c" fn lightjs_number_divide(f64, f64) u64;
const Timespec = extern struct { sec: c_long, nsec: c_long };
extern "c" fn clock_gettime(c_int, *Timespec) c_int;

const count = 16_384;
const passes = 64;
const samples = 9;
const seed = 0x4c69_6768_744a_5342;
const Profile = enum { bounded, raw_bits };
const Op = enum {
    read_baseline,
    number,
    boolean,
    to_number,
    to_boolean,
    to_int32,
    strict_equal,
    same_value,
    same_value_zero,
    add,
    subtract,
    multiply,
    divide,
    check_bits,
    abi_number,
    abi_boolean,
    abi_to_number,
    abi_to_boolean,
    abi_to_int32,
    abi_strict_equal,
    abi_same_value,
    abi_same_value_zero,
    abi_add,
    abi_subtract,
    abi_multiply,
    abi_divide,
    abi_check_bits,
};
const Inputs = struct {
    a: [count]f64,
    b: [count]f64,
    lhs: [count]Value,
    rhs: [count]Value,
    raw: [count]u64,
};
var inputs: Inputs = undefined;
var sink: u64 = 0;

fn next(state: *u64) u64 {
    state.* ^= state.* << 13;
    state.* ^= state.* >> 7;
    state.* ^= state.* << 17;
    return state.*;
}

fn generate(profile: Profile) void {
    const edges = [_]u64{
        0,                     0x8000_0000_0000_0000, 1,                     0x8000_0000_0000_0001,
        0x7ff0_0000_0000_0000, 0xfff0_0000_0000_0000, 0x7ff0_0000_0000_0001, 0xfff8_0000_0000_0003,
        0x7fef_ffff_ffff_ffff, 0x0010_0000_0000_0000, 0x41df_ffff_ffff_ffff, 0x41e0_0000_0000_0000,
        0x41f0_0000_0000_0000, 0x433f_ffff_ffff_ffff, 0x452f_ffff_ffff_ffff, 0x4530_0000_0000_0000,
    };
    const primitives = [_]Value{ Value.undefined_value, Value.null_value, Value.false_value, Value.true_value };
    var state: u64 = seed;
    for (0..count) |i| {
        const a = next(&state);
        const b = next(&state);
        inputs.a[i] = switch (profile) {
            .bounded => @as(f64, @floatFromInt(@as(i32, @bitCast(@as(u32, @truncate(a)))))) / 32.0,
            .raw_bits => @bitCast(a),
        };
        inputs.b[i] = switch (profile) {
            .bounded => @as(f64, @floatFromInt(@as(i32, @bitCast(@as(u32, @truncate(b)))))) / 32.0,
            .raw_bits => @bitCast(b),
        };
        // One in sixteen numbers is an explicit floating-point edge case.
        if (i % 16 == 0) inputs.a[i] = @bitCast(edges[(i / 16) % edges.len]);
        inputs.lhs[i] = if (i % 32 < 4) primitives[i % 4] else Value.number(inputs.a[i]);
        inputs.rhs[i] = if (i % 2 == 0) inputs.lhs[i] else Value.number(inputs.b[i]);
        inputs.raw[i] = if (i % 4 == 0) 0xfff8_0000_0000_0004 + (a & 0xffff) else inputs.lhs[i].bits;
    }
}

inline fn eval(comptime op: Op, i: usize) u64 {
    const a = inputs.a[i];
    const b = inputs.b[i];
    const lhs = inputs.lhs[i];
    const rhs = inputs.rhs[i];
    return switch (op) {
        .read_baseline => @as(u64, @bitCast(a)) +% @as(u64, @bitCast(b)),
        .number => Value.number(a).bits,
        .boolean => Value.boolean(inputs.raw[i] & 1 != 0).bits,
        .to_number => @bitCast(lhs.toNumber()),
        .to_boolean => @intFromBool(lhs.toBoolean()),
        .to_int32 => @as(u32, @bitCast(lhs.toInt32())),
        .strict_equal => @intFromBool(lhs.strictEqual(rhs)),
        .same_value => @intFromBool(lhs.sameValue(rhs)),
        .same_value_zero => @intFromBool(lhs.sameValueZero(rhs)),
        .add => Value.numberOp(.add, a, b).bits,
        .subtract => Value.numberOp(.subtract, a, b).bits,
        .multiply => Value.numberOp(.multiply, a, b).bits,
        .divide => Value.numberOp(.divide, a, b).bits,
        .check_bits => if (Value.fromBits(inputs.raw[i])) |v| @backingInt(v.kind()) else 0,
        .abi_number => lightjs_number(a),
        .abi_boolean => lightjs_boolean(@intCast(inputs.raw[i] & 1)),
        .abi_to_number => @bitCast(lightjs_to_number(lhs.bits)),
        .abi_to_boolean => lightjs_to_boolean(lhs.bits),
        .abi_to_int32 => @as(u32, @bitCast(lightjs_to_int32(lhs.bits))),
        .abi_strict_equal => lightjs_strict_equal(lhs.bits, rhs.bits),
        .abi_same_value => lightjs_same_value(lhs.bits, rhs.bits),
        .abi_same_value_zero => lightjs_same_value_zero(lhs.bits, rhs.bits),
        .abi_add => lightjs_number_add(a, b),
        .abi_subtract => lightjs_number_subtract(a, b),
        .abi_multiply => lightjs_number_multiply(a, b),
        .abi_divide => lightjs_number_divide(a, b),
        .abi_check_bits => lightjs_kind(inputs.raw[i]),
    };
}

noinline fn run(comptime op: Op) u64 {
    var sum: u64 = 0;
    for (0..passes) |_| {
        // Prevent repeated passes from becoming one hoisted calculation.
        std.mem.doNotOptimizeAway(&inputs);
        for (0..count) |i| sum +%= eval(op, i);
    }
    return sum;
}

fn now() u64 {
    var ts: Timespec = undefined;
    // Linux host CLOCK_MONOTONIC.
    if (clock_gettime(1, &ts) != 0) @panic("CLOCK_MONOTONIC failed");
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

pub fn main() !void {
    std.debug.print("Zig={s} mode={s} arch={s} cpu={s} Value_bytes={d}\n", .{
        builtin.zig_version_string, @tagName(builtin.mode), @tagName(builtin.cpu.arch), builtin.cpu.model.name, @sizeOf(Value),
    });
    std.debug.print("seed=0x{x} inputs={d} passes={d} ops/sample={d} warmups=2 samples={d} timer=CLOCK_MONOTONIC\n", .{
        seed, count, passes, count * passes, samples,
    });
    std.debug.print("bounded: signed int32/32; raw_bits: uniform u64; 1/16 edge numbers; 1/8 primitive tags; half equality pairs identical; check_bits: 1/4 invalid\n", .{});
    std.debug.print("Inputs generated before timing; checksum consumed; read baseline not subtracted; ABI includes validation and lost inlining/vectorization.\n", .{});
    std.debug.print("profile,operation,min_ns/op,median_ns/op,max_ns/op,range_percent,checksum\n", .{});
    inline for (comptime std.meta.tags(Profile)) |profile| {
        generate(profile);
        inline for (.{
            .{ Op.number, Op.abi_number },         .{ Op.boolean, Op.abi_boolean },
            .{ Op.to_number, Op.abi_to_number },   .{ Op.to_boolean, Op.abi_to_boolean },
            .{ Op.to_int32, Op.abi_to_int32 },     .{ Op.strict_equal, Op.abi_strict_equal },
            .{ Op.same_value, Op.abi_same_value }, .{ Op.same_value_zero, Op.abi_same_value_zero },
            .{ Op.add, Op.abi_add },               .{ Op.subtract, Op.abi_subtract },
            .{ Op.multiply, Op.abi_multiply },     .{ Op.divide, Op.abi_divide },
            .{ Op.check_bits, Op.abi_check_bits },
        }) |pair| {
            for (0..count) |i| if (eval(pair[0], i) != eval(pair[1], i)) return error.AbiMismatch;
        }
        inline for (comptime std.meta.tags(Op)) |op| {
            for (0..2) |_| @as(*volatile u64, &sink).* = run(op);
            var elapsed: [samples]u64 = undefined;
            for (&elapsed) |*ns| {
                const start = now();
                const result = run(op);
                ns.* = now() - start;
                @as(*volatile u64, &sink).* = result;
            }
            std.mem.sort(u64, &elapsed, {}, std.sort.asc(u64));
            const scale: f64 = count * passes;
            const median: f64 = @floatFromInt(elapsed[samples / 2]);
            std.debug.print("{s},{s},{d:.3},{d:.3},{d:.3},{d:.1},0x{x}\n", .{
                @tagName(profile), @tagName(op),                                          @as(f64, @floatFromInt(elapsed[0])) / scale,
                median / scale,    @as(f64, @floatFromInt(elapsed[samples - 1])) / scale, @as(f64, @floatFromInt(elapsed[samples - 1] - elapsed[0])) / median * 100,
                sink,
            });
        }
    }
}
