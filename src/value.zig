const std = @import("std");

pub const Value = packed struct(u64) {
    bits: u64,

    const tag_base: u64 = 0xfff8_0000_0000_0000;
    const infinity_bits: u64 = 0x7ff0_0000_0000_0000;
    const magnitude_mask: u64 = 0x7fff_ffff_ffff_ffff;
    pub const nan_bits: u64 = 0x7ff8_0000_0000_0000;
    pub const undefined_value: Value = .{ .bits = tag_base };
    pub const null_value: Value = .{ .bits = tag_base + 1 };
    pub const false_value: Value = .{ .bits = tag_base + 2 };
    pub const true_value: Value = .{ .bits = tag_base + 3 };

    pub const Kind = enum(u32) { number = 1, boolean = 2, null = 3, undefined = 4 };
    pub const NumberOp = enum { add, subtract, multiply, divide };

    comptime {
        @setFloatMode(.strict);
        std.debug.assert(@sizeOf(Value) == 8);
    }

    pub inline fn number(n: f64) Value {
        const bits: u64 = @bitCast(n);
        // Every incoming NaN must be normalized before it can overlap a tag.
        return .{ .bits = if (bits & magnitude_mask > infinity_bits) nan_bits else bits };
    }

    pub inline fn boolean(b: bool) Value {
        return .{ .bits = false_value.bits | @intFromBool(b) };
    }

    pub fn fromBits(bits: u64) ?Value {
        if (bits & magnitude_mask <= infinity_bits or bits == nan_bits or
            bits -% tag_base <= 3) return .{ .bits = bits };
        return null;
    }

    pub inline fn isNumber(self: Value) bool {
        return self.bits < tag_base;
    }

    pub fn kind(self: Value) Kind {
        if (self.isNumber()) return .number;
        return switch (self.bits) {
            undefined_value.bits => .undefined,
            null_value.bits => .null,
            false_value.bits, true_value.bits => .boolean,
            else => unreachable,
        };
    }

    pub inline fn toNumber(self: Value) f64 {
        if (self.isNumber()) return @bitCast(self.bits);
        return switch (self.bits) {
            undefined_value.bits => @bitCast(nan_bits),
            null_value.bits, false_value.bits => 0,
            true_value.bits => 1,
            else => unreachable,
        };
    }

    pub fn toBoolean(self: Value) bool {
        if (!self.isNumber()) return self.bits == true_value.bits;
        const magnitude = self.bits & magnitude_mask;
        return magnitude != 0 and magnitude <= infinity_bits;
    }

    pub fn toInt32(self: Value) i32 {
        const bits: u64 = @bitCast(self.toNumber());
        const exponent = (bits >> 52) & 0x7ff;
        // At exponent 84, every representable integer is a multiple of 2^32.
        if (exponent < 1023 or exponent >= 1107) return 0;
        const significand = (bits & 0x000f_ffff_ffff_ffff) | (1 << 52);
        const integer = if (exponent < 1075)
            significand >> @as(u6, @intCast(1075 - exponent))
        else
            significand << @as(u6, @intCast(exponent - 1075));
        const low: u32 = @truncate(integer);
        return @bitCast(if (bits >> 63 != 0) 0 -% low else low);
    }

    pub fn strictEqual(a: Value, b: Value) bool {
        if (a.isNumber() and b.isNumber()) return a.toNumber() == b.toNumber();
        return a.bits == b.bits;
    }

    pub inline fn sameValue(a: Value, b: Value) bool {
        return a.bits == b.bits;
    }

    pub fn sameValueZero(a: Value, b: Value) bool {
        return a.sameValue(b) or a.strictEqual(b);
    }

    pub inline fn numberOp(comptime op: NumberOp, a: f64, b: f64) Value {
        return number(switch (op) {
            .add => a + b,
            .subtract => a - b,
            .multiply => a * b,
            .divide => a / b,
        });
    }
};
