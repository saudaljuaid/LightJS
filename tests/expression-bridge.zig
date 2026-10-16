const lightjs = @import("lightjs");

extern "c" fn getchar() c_int;
extern "c" fn putchar(c_int) c_int;
extern "c" fn ferror(?*anyopaque) c_int;
extern "c" fn fflush(?*anyopaque) c_int;
extern "c" var stdin: ?*anyopaque;
extern "c" var stdout: ?*anyopaque;

fn emit(bytes: []const u8) !void {
    for (bytes) |byte| if (putchar(byte) < 0) return error.Output;
}

pub fn main() !void {
    var source: [4097]u8 = undefined;
    while (true) {
        const first = getchar();
        if (first < 0) {
            if (ferror(stdin) != 0) return error.Input;
            if (fflush(stdout) != 0) return error.Output;
            return;
        }
        var length: u32 = @intCast(first);
        for (1..4) |i| {
            const byte = getchar();
            if (byte < 0) return error.Truncated;
            length |= @as(u32, @intCast(byte)) << @as(u5, @intCast(i * 8));
        }
        if (length > source.len) return error.Length;
        for (source[0..length]) |*byte| {
            const input = getchar();
            if (input < 0) return error.Truncated;
            byte.* = @intCast(input);
        }
        const value = lightjs.evalNumberExpression(source[0..length]) catch |err| {
            try emit(@errorName(err));
            try emit("\n");
            continue;
        };
        var output: [17]u8 = undefined;
        for (0..16) |i| {
            const digit: u4 = @truncate(value.bits >> @as(u6, @intCast((15 - i) * 4)));
            output[i] = "0123456789abcdef"[digit];
        }
        output[16] = '\n';
        try emit(&output);
    }
}
