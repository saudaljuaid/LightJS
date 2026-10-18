const std = @import("std");
const lightjs = @import("lightjs");
const eq = std.testing.expectEqual;
const err = std.testing.expectError;

fn check(source: []const u8, bits: u64) !void {
    const result = try lightjs.evalNumberProgram(source);
    try eq(lightjs.Value.Kind.number, result.kind());
    try eq(bits, result.bits);
}

test "numeric programs bind names locally and reassign in sequence" {
    for ([_]struct { []const u8, f64 }{
        .{ "1 + 2 * 3", 7 },
        .{ "let x=2;let y=x*3;x=x+1;x+y", 9 },
        .{ "let price=12;let quantity=3;price=price+2;price*quantity; \n", 42 },
        .{ "let x=1;x=x+2;x=x*3;(x+1)/2", 5 },
        .{ "let x=1;let X=2;x+X", 3 },
        .{ "let letter=1;let let1=2;let let_=3;let let$=4;letter+let1+let_+let$", 10 },
        .{ "let $=1;let _=2;let $a_9=3;$+_+$a_9", 6 },
        .{ "let x=1;let x1=2;x+x1", 3 },
        .{ "\tlet\nx\r=\t.5e1;\nx = +(x * 2) - -1; x", 11 },
    }) |case| try check(case[0], lightjs.Value.number(case[1]).bits);
    for ([_][]const u8{ "x", "x=1;x", "let x=x;x", "let x=1;X", "let x=1;x1", "NaN", "Infinity", "undefined" }) |source|
        try err(error.UnknownIdentifier, lightjs.evalNumberProgram(source));
    for ([_][]const u8{ "let x=1;let x=2;x", "let x=1;let x=x+1;x" }) |source|
        try err(error.DuplicateBinding, lightjs.evalNumberProgram(source));
    try check("let x=7;x", lightjs.Value.number(7).bits);
    try err(error.UnknownIdentifier, lightjs.evalNumberProgram("x"));
}

test "numeric programs reject reserved identifiers in every position" {
    const reserved = "await break case catch class const continue debugger default delete do else enum export extends false finally for function if import in instanceof let new null return super switch this throw true try typeof var void while with yield implements interface package private protected public static eval arguments";
    var names = std.mem.tokenizeScalar(u8, reserved, ' ');
    var buffer: [80]u8 = undefined;
    while (names.next()) |name| {
        try err(error.InvalidSyntax, lightjs.evalNumberProgram(try std.fmt.bufPrint(&buffer, "let {s}=1;1", .{name})));
        try err(error.InvalidSyntax, lightjs.evalNumberProgram(try std.fmt.bufPrint(&buffer, "{s}=1;1", .{name})));
        try err(error.InvalidSyntax, lightjs.evalNumberProgram(name));
    }
}

test "numeric programs preserve binary64 bits through bindings" {
    for ([_]struct { []const u8, u64 }{
        .{ "let x=-0;x", 0x8000_0000_0000_0000 },
        .{ "let x=-0;x=x+-0;x", 0x8000_0000_0000_0000 },
        .{ "let zero=-0;1/zero", 0xfff0_0000_0000_0000 },
        .{ "let x=0/0;x=-x;x", lightjs.Value.nan_bits },
        .{ "let x=1e309;x-x", lightjs.Value.nan_bits },
        .{ "let x=9007199254740993;x=x+1;x", 0x4340_0000_0000_0000 },
        .{ "let x=5e-324;x", 1 },
        .{ "let x=-2e-324;x", 0x8000_0000_0000_0000 },
        .{ "let x=2.2250738585072014e-308;x", 0x0010_0000_0000_0000 },
    }) |case| try check(case[0], case[1]);
}

test "numeric programs require a final expression and consume unsupported syntax" {
    for ([_][]const u8{
        "",        " \n",              "let x=1;",    "let x=1",    "let x=1 x",           "let x=1;x=2",    "let x=1;x=2;", "1;2",         "1;;",           "1;let x=2;",
        "let=1;1", "let 1x=2;1",       "let x;1",     "let x==1;x", "let x=1;let x1=1x;x", "let x=1;x+=2;x", "let x=1;++x",  "let x=1;x--", "let x=1;(x=2)", "1<2",
        "1<=2",    "1>2",              "1>=2",        "1===2",      "1!==2",               "true",           "'1'",          "\"1\"",       "const x=1;x",   "var x=1;x",
        "{1}",     "function f(){};1", "let x=1;x()", "1//2",       "1/*x*/",              "01",             "0x10",         "1_000",       "1e+",           "1 2",
        "1x",      "1\x00",            "1\x0b",       "1\xff",      "++1",                 "--1",            "1**2",         "let x=1;x x",
    }) |source| try err(error.InvalidSyntax, lightjs.evalNumberProgram(source));
    try err(error.InvalidSyntax, lightjs.evalNumberExpression("let x=1;x"));
    try err(error.InvalidSyntax, lightjs.evalNumberComparison("let x=1;x<2"));
    try eq(lightjs.Value.number(7).bits, (try lightjs.evalNumberExpression("1+2*3")).bits);
    try eq(lightjs.Value.true_value.bits, (try lightjs.evalNumberComparison("1+2*3===7")).bits);
}

fn repeated(comptime text: []const u8, comptime count: usize) [text.len * count]u8 {
    @setEvalBranchQuota(10_000);
    var result: [text.len * count]u8 = undefined;
    for (0..count) |i| @memcpy(result[i * text.len ..][0..text.len], text);
    return result;
}

test "numeric program limits bound source, bindings, and each fresh expression depth" {
    try check("1" ++ repeated(" ", 4095), lightjs.Value.number(1).bits);
    try err(error.LimitExceeded, lightjs.evalNumberProgram("1" ++ repeated(" ", 4096)));
    var source: [2048]u8 = undefined;
    var length: usize = 0;
    for (0..64) |i| length += (try std.fmt.bufPrint(source[length..], "let n{d}=1;", .{i})).len;
    const tail = try std.fmt.bufPrint(source[length..], "n0=n0+1;n63+n0", .{});
    try check(source[0 .. length + tail.len], lightjs.Value.number(3).bits);
    const overflow = try std.fmt.bufPrint(source[length..], "let extra=1;extra", .{});
    try err(error.LimitExceeded, lightjs.evalNumberProgram(source[0 .. length + overflow.len]));
    inline for (.{ repeated("(", 64) ++ "1" ++ repeated(")", 64), repeated("- ", 64) ++ "1", repeated("(", 32) ++ repeated("- ", 32) ++ "1" ++ repeated(")", 32) }) |operand| {
        try check("let x=" ++ operand ++ ";x=" ++ operand ++ ";" ++ operand, lightjs.Value.number(1).bits);
    }
    inline for (.{ repeated("(", 65) ++ "1" ++ repeated(")", 65), repeated("- ", 65) ++ "1", repeated("(", 32) ++ repeated("- ", 33) ++ "1" ++ repeated(")", 32) }) |operand| {
        try err(error.LimitExceeded, lightjs.evalNumberProgram("let x=" ++ operand ++ ";x"));
        try err(error.LimitExceeded, lightjs.evalNumberProgram("let x=1;x=" ++ operand ++ ";x"));
        try err(error.LimitExceeded, lightjs.evalNumberProgram("let x=1;" ++ operand));
    }
    try check("let x=1;x" ++ repeated("+1", 2040), lightjs.Value.number(2041).bits);
    try check("let x=1;x" ++ repeated("*1", 2040), lightjs.Value.number(1).bits);
    try check("let x=0;" ++ repeated("x=x+1;", 600) ++ "x", lightjs.Value.number(600).bits);
}
