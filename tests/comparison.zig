const std = @import("std");
const lightjs = @import("lightjs");

fn check(source: []const u8, expected: bool) !void {
    const result = try lightjs.evalNumberComparison(source);
    try std.testing.expectEqual(lightjs.Value.Kind.boolean, result.kind());
    try std.testing.expectEqual(lightjs.Value.boolean(expected).bits, result.bits);
}

test "numeric comparisons return canonical booleans with arithmetic precedence" {
    for ([_]struct { []const u8, bool }{
        .{ "1 < 2", true },
        .{ "2 < 1", false },
        .{ "2 <= 2", true },
        .{ "3 <= 2", false },
        .{ "2 > 1", true },
        .{ "1 > 2", false },
        .{ "2 >= 2", true },
        .{ "1 >= 2", false },
        .{ "2 === 2", true },
        .{ "2 === 3", false },
        .{ "2 !== 3", true },
        .{ "2 !== 2", false },
        .{ "2 + 3 * 4 < 3 * 5 - 0", true },
        .{ "(1 + 2) * 3 >= 8 + 2 / 2", true },
        .{ "(1 + 2) < (3 * 4)", true },
        .{ "\t\r\n(.5 + 1.) * 2e+1 <= 3E1 \n", true },
        .{ "- + - +2 < 3", true },
        .{ "-0 === 0", true },
        .{ "-0 !== 0", false },
        .{ "-0 < 0", false },
        .{ "-0 >= 0", true },
        .{ "0 / 0 === 0 / 0", false },
        .{ "0 / 0 !== 0 / 0", true },
        .{ "0 / 0 !== 1", true },
        .{ "1e309 === 1 / 0", true },
        .{ "-1e309 === 1 / -0", true },
        .{ "1 / -0 < 1 / 0", true },
        .{ "1e309 <= 1e309", true },
        .{ "1e309 > 1e309", false },
        .{ "9007199254740993 === 9007199254740992", true },
        .{ "9007199254740993 > 9007199254740992", false },
        .{ "1.00000000000000011102230246251565404236316680908203125 === 1", true },
        .{ "5e-324 > 0", true },
        .{ "-5e-324 < 0", true },
        .{ "2e-324 === 0", true },
        .{ "-2e-324 === -0", true },
        .{ "2.2250738585072014e-308 > 5e-324", true },
    }) |case| try check(case[0], case[1]);
    inline for (.{ "<", "<=", ">", ">=" }) |op| {
        try check("0 / 0 " ++ op ++ " 1", false);
        try check("1 " ++ op ++ " 0 / 0", false);
    }
}

test "numeric comparisons reject unsupported syntax and consume every byte" {
    for ([_][]const u8{
        "",       " \t\r\n", "1",      "<1",      "1<",       "1<2<3",   "1===2!==3", "(1<2)",  "(1<2)<3", "1<(2<3)",
        "true<1", "1<false", "1==2",   "1!=2",    "1=2",      "1< =2",   "1> =2",     "1= ==2", "1! ==2",  "1====2",
        "1!===2", "1<<2",    "1>>2",   "1<>2",    "1=>2",     "1=<2",    "1<2&&3",    "1||2<3", "!1<2",    "1<2?3:4",
        "1<2;",   "1<2 3",   "1<2)",   "1<2\x00", "1<2\x0b",  "1<2\xff", "01<2",      "1<0x10", "NaN<2",   "1<Infinity",
        "++1<2",  "1<--2",   "1**2<3", "1//2<3",  "1<2/*x*/", "1%2<3",   "'1'<2",     "x<2",    "1<.e2",   "1<1e+",
    }) |source| try std.testing.expectError(error.InvalidSyntax, lightjs.evalNumberComparison(source));
    inline for (.{ "<", "<=", ">", ">=", "===", "!==" }) |op|
        try std.testing.expectError(error.InvalidSyntax, lightjs.evalNumberExpression("1" ++ op ++ "2"));
}

fn repeated(comptime text: []const u8, comptime count: usize) [text.len * count]u8 {
    @setEvalBranchQuota(10_000);
    var result: [text.len * count]u8 = undefined;
    for (0..count) |i| @memcpy(result[i * text.len ..][0..text.len], text);
    return result;
}

test "numeric comparisons enforce input and combined depth limits on either side" {
    try check("1<2" ++ repeated(" ", 4093), true);
    try std.testing.expectError(error.LimitExceeded, lightjs.evalNumberComparison("1<2" ++ repeated(" ", 4094)));
    inline for (.{ repeated("(", 64) ++ "1" ++ repeated(")", 64), repeated("- ", 64) ++ "1", repeated("(", 32) ++ repeated("- ", 32) ++ "1" ++ repeated(")", 32) }) |operand| {
        try check(operand ++ "<2", true);
        try check("0<" ++ operand, true);
        try check(operand ++ "===" ++ operand, true);
    }
    inline for (.{ repeated("(", 65) ++ "1" ++ repeated(")", 65), repeated("- ", 65) ++ "1", repeated("(", 32) ++ repeated("- ", 33) ++ "1" ++ repeated(")", 32) }) |operand| {
        try std.testing.expectError(error.LimitExceeded, lightjs.evalNumberComparison(operand ++ "<2"));
        try std.testing.expectError(error.LimitExceeded, lightjs.evalNumberComparison("0<" ++ operand));
    }
    try check("1" ++ repeated("+1", 1022) ++ "<1" ++ repeated("+1", 1023), true);
    try check("1" ++ repeated("*1", 1023) ++ ">=1" ++ repeated("*1", 1022), true);
}
