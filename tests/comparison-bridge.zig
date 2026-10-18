pub fn main() !void {
    return @import("expression-bridge.zig").run(@import("lightjs").evalNumberComparison);
}
