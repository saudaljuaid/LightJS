const std = @import("std");
const Value = @import("value.zig").Value;
const Error = error{ InvalidSyntax, LimitExceeded };
const ParseError = Error || error{UnknownIdentifier};
const max_depth = 64;

pub fn eval(source: []const u8) Error!Value {
    return evaluate(source, false);
}

pub fn evalComparison(source: []const u8) Error!Value {
    return evaluate(source, true);
}

fn evaluate(source: []const u8, comptime comparison: bool) Error!Value {
    try validate(source);
    var parser = Parser{ .source = source };
    const result = (if (comparison) parser.comparison() else parser.sum(0)) catch |err| switch (err) {
        error.UnknownIdentifier => unreachable, // These APIs never enable name lookup.
        else => |e| return e,
    };
    if (parser.peek() != null) return error.InvalidSyntax;
    return result;
}

fn validate(source: []const u8) Error!void {
    if (source.len > 4096) return error.LimitExceeded;
    for (source, 0..) |c, i| {
        if (i + 1 < source.len and source[i + 1] == c and
            (c == '+' or c == '-' or c == '*')) return error.InvalidSyntax;
    }
}

pub fn evalProgram(source: []const u8) (ParseError || error{DuplicateBinding})!Value {
    try validate(source);
    var bindings = Bindings{};
    var parser = Parser{ .source = source, .bindings = &bindings };
    while (true) {
        _ = parser.peek();
        const start = parser.pos;
        const token = parser.identifier();
        const declaration = if (token) |name| std.mem.eql(u8, name, "let") else false;
        if (declaration) _ = parser.peek();
        const name = if (declaration) parser.identifier() else token;
        _ = parser.peek();
        if (declaration or (name != null and parser.byte() == '=')) {
            const target = name orelse return error.InvalidSyntax;
            if (reserved(target) or !parser.eat('=')) return error.InvalidSyntax;
            const index = bindings.find(target);
            if (!declaration and index == null) return error.UnknownIdentifier;
            const value = try parser.sum(0);
            _ = parser.peek();
            if (!parser.eat(';')) return error.InvalidSyntax;
            if (declaration) {
                if (index != null) return error.DuplicateBinding;
                if (bindings.count == bindings.entries.len) return error.LimitExceeded;
                bindings.entries[bindings.count] = .{ .name = target, .value = value };
                bindings.count += 1;
            } else bindings.entries[index.?].value = value;
            continue;
        }
        parser.pos = start;
        const result = try parser.sum(0);
        _ = parser.peek();
        _ = parser.eat(';');
        if (parser.peek() != null) return error.InvalidSyntax;
        return result;
    }
}

const Bindings = struct {
    entries: [64]struct { name: []const u8, value: Value } = undefined,
    count: usize = 0,

    fn find(self: *const Bindings, name: []const u8) ?usize {
        for (self.entries[0..self.count], 0..) |entry, i| {
            if (std.mem.eql(u8, entry.name, name)) return i;
        }
        return null;
    }
};

fn nameStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_' or c == '$';
}

fn reserved(name: []const u8) bool {
    var words = std.mem.tokenizeScalar(u8, "await break case catch class const continue debugger default delete do else " ++
        "enum export extends false finally for function if import in instanceof let new null return super switch " ++
        "this throw true try typeof var void while with yield implements interface package private protected " ++
        "public static eval arguments", ' ');
    while (words.next()) |word| if (std.mem.eql(u8, name, word)) return true;
    return false;
}

const Parser = struct {
    source: []const u8,
    pos: usize = 0,
    bindings: ?*Bindings = null,

    fn identifier(self: *Parser) ?[]const u8 {
        const start = self.pos;
        if (!nameStart(self.byte() orelse return null)) return null;
        self.pos += 1;
        while (self.byte()) |c| {
            if (!nameStart(c) and !std.ascii.isDigit(c)) break;
            self.pos += 1;
        }
        return self.source[start..self.pos];
    }

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

    fn comparison(self: *Parser) ParseError!Value {
        const lhs = try self.sum(0);
        const op = self.peek() orelse return error.InvalidSyntax;
        self.pos += 1;
        const equal = self.eat('=');
        if (op == '=' or op == '!') {
            if (!equal or !self.eat('=')) return error.InvalidSyntax;
        } else if (op != '<' and op != '>') return error.InvalidSyntax;
        const rhs = try self.sum(0);
        const a = lhs.toNumber();
        const b = rhs.toNumber();
        return Value.boolean(switch (op) {
            '<' => if (equal) a <= b else a < b,
            '>' => if (equal) a >= b else a > b,
            '=' => lhs.strictEqual(rhs),
            '!' => !lhs.strictEqual(rhs),
            else => unreachable,
        });
    }

    fn sum(self: *Parser, depth: usize) ParseError!Value {
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

    fn product(self: *Parser, depth: usize) ParseError!Value {
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

    fn prefix(self: *Parser, depth: usize) ParseError!Value {
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
        if (self.bindings) |bindings| {
            if (self.identifier()) |name| {
                if (reserved(name)) return error.InvalidSyntax;
                const index = bindings.find(name) orelse return error.UnknownIdentifier;
                return bindings.entries[index].value;
            }
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
