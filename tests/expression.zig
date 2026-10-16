const std = @import("std");
const lightjs = @import("lightjs");
const eq = std.testing.expectEqual;

fn check(source: []const u8, bits: u64) !void {
    const result = try lightjs.evalNumberExpression(source);
    try std.testing.expect(result.isNumber());
    try eq(bits, result.bits);
}

test "numeric expressions follow precedence, associativity, and unary grouping" {
    for ([_]struct { []const u8, f64 }{
        .{ "1 + 2 * 3", 7 },
        .{ "(1 + 2) * 3", 9 },
        .{ "8 / 4 / 2", 1 },
        .{ "8 - 4 - 2", 2 },
        .{ "- + - +2", 2 },
        .{ "1 + +2", 3 },
        .{ "1 - -2", 3 },
        .{ "1+-2", -1 },
        .{ "1-+2", -1 },
        .{ "\t\r\n(.5 + 1.) * 2e+1 \n", 30 },
        .{ "2E-2 / .1", 0.19999999999999998 },
    }) |case| try check(case[0], lightjs.Value.number(case[1]).bits);
}

test "numeric expressions preserve IEEE bits and decimal rounding" {
    for ([_]struct { []const u8, u64 }{
        .{ "-0", 0x8000_0000_0000_0000 },
        .{ "-(0)", 0x8000_0000_0000_0000 },
        .{ "- -0", 0 },
        .{ "1 / -0", 0xfff0_0000_0000_0000 },
        .{ "0 / 0", lightjs.Value.nan_bits },
        .{ "-(0 / 0)", lightjs.Value.nan_bits },
        .{ "-0 + -0", 0x8000_0000_0000_0000 },
        .{ "0 + -0", 0 },
        .{ "-0 - 0", 0x8000_0000_0000_0000 },
        .{ "0 * -1", 0x8000_0000_0000_0000 },
        .{ "9007199254740993", 0x4340_0000_0000_0000 },
        .{ "9007199254740995", 0x4340_0000_0000_0002 },
        .{ "1.00000000000000011102230246251565404236316680908203125", 0x3ff0_0000_0000_0000 },
        .{ "1.00000000000000011102230246251565404236316680908203126", 0x3ff0_0000_0000_0001 },
        .{ "1.7976931348623157e308", 0x7fef_ffff_ffff_ffff },
        .{ "1e309", 0x7ff0_0000_0000_0000 },
        .{ "-1e309", 0xfff0_0000_0000_0000 },
        .{ "2.2250738585072014e-308", 0x0010_0000_0000_0000 },
        .{ "5e-324", 1 },
        .{ "2e-324", 0 },
        .{ "-2e-324", 0x8000_0000_0000_0000 },
    }) |case| try check(case[0], case[1]);
}

test "numeric expressions reject unsupported syntax and consume every byte" {
    for ([_][]const u8{
        "",      " \t\r\n", "()",   "(1",    "1)",       "1 2",    "1;",     "1+",     "*1",
        "++1",   "--1",     "1++2", "1--2",  "1**2",     "1 ** 2", "1 +++2", "1 ---2", "01",
        "00.5",  "-01",     "1e",   "1e+",   "1e-",      ".",      ".e2",    "1..2",   "1.2.3",
        "0x10",  "0b10",    "0o10", "1_000", "Infinity", "NaN",    "x",      "'1'",    "\"1\"",
        "1//2",  "1/*x*/",  "1%2",  "1^2",   "1=2",      "1,2",    "1\x00",  "\x001",  "1\x0b",
        "1\x0c", "1\xff",
    }) |source| try std.testing.expectError(error.InvalidSyntax, lightjs.evalNumberExpression(source));
}

fn repeated(comptime text: []const u8, comptime count: usize) [text.len * count]u8 {
    @setEvalBranchQuota(10_000);
    var result: [text.len * count]u8 = undefined;
    for (0..count) |i| @memcpy(result[i * text.len ..][0..text.len], text);
    return result;
}

test "numeric expression length and combined recursion limits are deterministic" {
    var exact: [4096]u8 = @splat(' ');
    exact[0] = '1';
    try check(&exact, lightjs.Value.number(1).bits);
    try std.testing.expectError(error.LimitExceeded, lightjs.evalNumberExpression("1" ++ repeated(" ", 4096)));
    try check(repeated("(", 64) ++ "1" ++ repeated(")", 64), lightjs.Value.number(1).bits);
    try std.testing.expectError(error.LimitExceeded, lightjs.evalNumberExpression(repeated("(", 65) ++ "1" ++ repeated(")", 65)));
    try check(repeated("- ", 64) ++ "1", lightjs.Value.number(1).bits);
    try std.testing.expectError(error.LimitExceeded, lightjs.evalNumberExpression(repeated("- ", 65) ++ "1"));
    try check(repeated("(", 32) ++ repeated("- ", 32) ++ "1" ++ repeated(")", 32), lightjs.Value.number(1).bits);
    try std.testing.expectError(error.LimitExceeded, lightjs.evalNumberExpression(repeated("(", 32) ++ repeated("- ", 33) ++ "1" ++ repeated(")", 32)));
    try check("1" ++ repeated("+1", 2047), lightjs.Value.number(2048).bits);
    try check("1" ++ repeated("*1", 2047), lightjs.Value.number(1).bits);
    try check("1" ++ repeated("+-1", 1365), lightjs.Value.number(-1364).bits);
}
