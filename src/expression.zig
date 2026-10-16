const std = @import("std");
const Value = @import("value.zig").Value;
const Error = error{ InvalidSyntax, LimitExceeded };
const max_depth = 64;

pub fn eval(source: []const u8) Error!Value {
    if (source.len > 4096) return error.LimitExceeded;
    for (source, 0..) |c, i| {
        if (i + 1 < source.len and source[i + 1] == c and
            (c == '+' or c == '-' or c == '*')) return error.InvalidSyntax;
    }
    var parser = Parser{ .source = source };
    const result = try parser.sum(0);
    if (parser.peek() != null) return error.InvalidSyntax;
    return result;
}

const Parser = struct {
    source: []const u8,
    pos: usize = 0,

    fn byte(self: *Parser) ?u8 {
        return if (self.pos < self.source.len) self.source[self.pos] else null;
    }

    fn peek(self: *Parser) ?u8 {
        while (self.byte()) |c| {
            switch (c) {
                ' ', '\t', '\r', '\n' => self.pos += 1,
                else => return c,
            }
        }
        return null;
    }

    fn eat(self: *Parser, c: u8) bool {
        if (self.byte() != c) return false;
        self.pos += 1;
        return true;
    }

    fn sum(self: *Parser, depth: usize) Error!Value {
        var lhs = try self.product(depth);
        while (self.peek()) |op| {
            if (op != '+' and op != '-') break;
            self.pos += 1;
            const rhs = try self.product(depth);
            lhs = switch (op) {
                '+' => Value.numberOp(.add, lhs.toNumber(), rhs.toNumber()),
                else => Value.numberOp(.subtract, lhs.toNumber(), rhs.toNumber()),
            };
        }
        return lhs;
    }

    fn product(self: *Parser, depth: usize) Error!Value {
        var lhs = try self.prefix(depth);
        while (self.peek()) |op| {
            if (op != '*' and op != '/') break;
            self.pos += 1;
            const rhs = try self.prefix(depth);
            lhs = switch (op) {
                '*' => Value.numberOp(.multiply, lhs.toNumber(), rhs.toNumber()),
                else => Value.numberOp(.divide, lhs.toNumber(), rhs.toNumber()),
            };
        }
        return lhs;
    }

    fn prefix(self: *Parser, depth: usize) Error!Value {
        const op = self.peek() orelse return error.InvalidSyntax;
        if (op == '+' or op == '-' or op == '(') {
            // Bound the combined pending parentheses and unary prefixes, even in ReleaseFast.
            if (depth >= max_depth) return error.LimitExceeded;
            self.pos += 1;
            if (op == '(') {
                const result = try self.sum(depth + 1);
                _ = self.peek();
                if (!self.eat(')')) return error.InvalidSyntax;
                return result;
            }
            const operand = try self.prefix(depth + 1);
            return if (op == '-') Value.number(-operand.toNumber()) else operand;
        }
        return self.literal();
    }

    fn digits(self: *Parser) void {
        while (self.byte()) |c| {
            if (c < '0' or c > '9') break;
            self.pos += 1;
        }
    }

    fn literal(self: *Parser) Error!Value {
        const start = self.pos;
        if (self.eat('0')) {
            if (self.byte()) |c| if (c >= '0' and c <= '9') return error.InvalidSyntax;
        } else self.digits();
        const integer_end = self.pos;
        if (self.eat('.')) {
            self.digits();
            if (integer_end == start and self.pos == start + 1) return error.InvalidSyntax;
        } else if (integer_end == start) return error.InvalidSyntax;
        if (self.eat('e') or self.eat('E')) {
            if (!self.eat('+')) _ = self.eat('-');
            const exponent_start = self.pos;
            self.digits();
            if (self.pos == exponent_start) return error.InvalidSyntax;
        }
        const number = std.fmt.parseFloat(f64, self.source[start..self.pos]) catch return error.InvalidSyntax;
        return Value.number(number);
    }
};
