const lightjs = @import("lightjs");

pub fn main() !void {
    return @import("expression-bridge.zig").run(lightjs.evalNumberProgram);
}
