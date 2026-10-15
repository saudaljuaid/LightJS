pub const Value = @import("value.zig").Value;

export fn lightjs_number(n: f64) u64 {
    return Value.number(n).bits;
}
export fn lightjs_boolean(b: u32) u64 {
    return Value.boolean(b != 0).bits;
}
export fn lightjs_null() u64 {
    return Value.null_value.bits;
}
export fn lightjs_undefined() u64 {
    return Value.undefined_value.bits;
}
export fn lightjs_kind(bits: u64) u32 {
    const value = Value.fromBits(bits) orelse return 0;
    return @backingInt(value.kind());
}
export fn lightjs_to_number(bits: u64) f64 {
    const value = Value.fromBits(bits) orelse return @bitCast(Value.nan_bits);
    return value.toNumber();
}
export fn lightjs_to_boolean(bits: u64) u32 {
    const value = Value.fromBits(bits) orelse return 0;
    return @intFromBool(value.toBoolean());
}
export fn lightjs_to_int32(bits: u64) i32 {
    const value = Value.fromBits(bits) orelse return 0;
    return value.toInt32();
}
export fn lightjs_strict_equal(a: u64, b: u64) u32 {
    return equal(a, b, Value.strictEqual);
}
export fn lightjs_same_value(a: u64, b: u64) u32 {
    return equal(a, b, Value.sameValue);
}
export fn lightjs_same_value_zero(a: u64, b: u64) u32 {
    return equal(a, b, Value.sameValueZero);
}
fn equal(a: u64, b: u64, comptime compare: anytype) u32 {
    const lhs = Value.fromBits(a) orelse return 0;
    const rhs = Value.fromBits(b) orelse return 0;
    return @intFromBool(compare(lhs, rhs));
}
export fn lightjs_number_add(a: f64, b: f64) u64 {
    return Value.numberOp(.add, a, b).bits;
}
export fn lightjs_number_subtract(a: f64, b: f64) u64 {
    return Value.numberOp(.subtract, a, b).bits;
}
export fn lightjs_number_multiply(a: f64, b: f64) u64 {
    return Value.numberOp(.multiply, a, b).bits;
}
export fn lightjs_number_divide(a: f64, b: f64) u64 {
    return Value.numberOp(.divide, a, b).bits;
}
