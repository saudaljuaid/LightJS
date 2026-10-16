const std = @import("std");
const Value = @import("lightjs").Value;
const expect = std.testing.expect;
const eq = std.testing.expectEqual;

test {
    _ = @import("expression.zig");
}

test "numbers retain every non-NaN bit and normalize all NaNs" {
    const edges = [_]u64{
        0,                     0x8000_0000_0000_0000, 1,                     0x8000_0000_0000_0001,
        0x000f_ffff_ffff_ffff, 0x0010_0000_0000_0000, 0x7fef_ffff_ffff_ffff, 0xffef_ffff_ffff_ffff,
        0x7ff0_0000_0000_0000, 0xfff0_0000_0000_0000, 0x7ff0_0000_0000_0001, 0xfff0_0000_0000_0001,
        0x7ff8_0000_0000_0001, 0xfff8_0000_0000_0000, 0xfff8_0000_0000_0001, 0xfff8_0000_0000_0002,
        0xfff8_0000_0000_0003, 0xffff_ffff_ffff_ffff,
    };
    for (edges) |bits| try checkNumber(bits);
    var rng = std.Random.DefaultPrng.init(0x4c69_6768_744a_5321);
    for (0..100_000) |_| try checkNumber(rng.random().int(u64));
}

fn checkNumber(bits: u64) !void {
    const n: f64 = @bitCast(bits);
    const v = Value.number(n);
    try expect(v.isNumber());
    try eq(Value.Kind.number, v.kind());
    try eq(if (std.math.isNan(n)) Value.nan_bits else bits, v.bits);
    try eq(v.bits, @as(u64, @bitCast(v.toNumber())));
    try eq(v, Value.fromBits(v.bits).?);
}

test "raw input rejects noncanonical NaNs and reserved tags" {
    for ([_]u64{
        0x7ff0_0000_0000_0001, 0x7ff8_0000_0000_0001,
        0xfff0_0000_0000_0001, 0xfff8_0000_0000_0004,
        0xfff9_0000_0000_0000, 0xffff_ffff_ffff_ffff,
    }) |bits| try expect(Value.fromBits(bits) == null);
    for ([_]Value{ Value.undefined_value, Value.null_value, Value.false_value, Value.true_value }) |v| {
        try eq(v, Value.fromBits(v.bits).?);
        try expect(!v.isNumber());
    }
}

test "primitive conversion keeps types distinct" {
    try eq(Value.Kind.undefined, Value.undefined_value.kind());
    try eq(Value.Kind.null, Value.null_value.kind());
    try eq(Value.Kind.boolean, Value.boolean(true).kind());
    try eq(Value.false_value, Value.boolean(false));
    try eq(Value.true_value, Value.boolean(true));
    try expect(std.math.isNan(Value.undefined_value.toNumber()));
    try eq(@as(f64, 0), Value.null_value.toNumber());
    try eq(@as(f64, 0), Value.false_value.toNumber());
    try eq(@as(f64, 1), Value.true_value.toNumber());
    for ([_]Value{
        Value.undefined_value, Value.null_value,   Value.false_value,
        Value.number(0),       Value.number(-0.0), Value.number(std.math.nan(f64)),
    }) |v| try expect(!v.toBoolean());
    for ([_]Value{
        Value.true_value,                    Value.number(1),                 Value.number(-1),
        Value.number(@bitCast(@as(u64, 1))), Value.number(std.math.inf(f64)),
    }) |v| try expect(v.toBoolean());
}

test "all primitive pairs follow the three JavaScript equality relations" {
    const values = [_]Value{
        Value.number(0),                 Value.number(-0.0),    Value.number(1),  Value.number(-1),
        Value.number(std.math.nan(f64)), Value.undefined_value, Value.null_value, Value.false_value,
        Value.true_value,
    };
    const strict = [_]u16{ 3, 3, 4, 8, 0, 32, 64, 128, 256 };
    const same = [_]u16{ 1, 2, 4, 8, 16, 32, 64, 128, 256 };
    const zero = [_]u16{ 3, 3, 4, 8, 16, 32, 64, 128, 256 };
    for (values, 0..) |a, i| {
        for (values, 0..) |b, j| {
            const bit = @as(u16, 1) << @as(u4, @intCast(j));
            try eq(strict[i] & bit != 0, a.strictEqual(b));
            try eq(same[i] & bit != 0, a.sameValue(b));
            try eq(zero[i] & bit != 0, a.sameValueZero(b));
        }
    }
}

test "ToInt32 truncates and wraps without out-of-range float casts" {
    const inputs = [_]f64{
        0,                     -0.0,       0.9,               -0.9,              1.9,         -1.9,             2147483647,       2147483648,
        -2147483649,           4294967295, 4294967296,        4294967297,        -4294967297, 9007199254740991, 9007199254740992, 0x1.0000000000001p83,
        -0x1.0000000000001p83, 0x1p84,     std.math.inf(f64), std.math.nan(f64),
    };
    const expected = [_]i32{
        0,           0,  0, 0, 1,  -1, 2147483647, -2147483648,
        2147483647,  -1, 0, 1, -1, -1, 0,          -2147483648,
        -2147483648, 0,  0, 0,
    };
    for (inputs, expected) |n, integer| try eq(integer, Value.number(n).toInt32());
    try eq(@as(i32, 0), Value.undefined_value.toInt32());
    try eq(@as(i32, 0), Value.null_value.toInt32());
    try eq(@as(i32, 0), Value.false_value.toInt32());
    try eq(@as(i32, 1), Value.true_value.toInt32());
}

test "Number operations preserve IEEE results and canonicalize NaNs" {
    const negative_zero: u64 = 0x8000_0000_0000_0000;
    const inf = std.math.inf(f64);
    try eq(negative_zero, Value.numberOp(.add, -0.0, -0.0).bits);
    try eq(@as(u64, 0), Value.numberOp(.add, 0, -0.0).bits);
    try eq(negative_zero, Value.numberOp(.subtract, -0.0, 0).bits);
    try eq(negative_zero, Value.numberOp(.multiply, 0, -1).bits);
    try eq(negative_zero, Value.numberOp(.divide, -1, inf).bits);
    try eq(Value.number(inf), Value.numberOp(.divide, 1, 0));
    try eq(Value.number(-inf), Value.numberOp(.divide, 1, -0.0));
    try eq(Value.nan_bits, Value.numberOp(.divide, 0, 0).bits);
    try eq(Value.nan_bits, Value.numberOp(.subtract, inf, inf).bits);
    try eq(Value.nan_bits, Value.numberOp(.multiply, inf, 0).bits);
    try eq(Value.number(9007199254740992), Value.numberOp(.add, 9007199254740992, 1));
    try eq(Value.number(inf), Value.numberOp(.multiply, std.math.floatMax(f64), 2));
}
