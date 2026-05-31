const std = @import("std");

pub const Baton = struct {
    counter: i32,
    module_cid: []const u8,

    pub fn save(self: Baton, allocator: std.mem.Allocator, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        const msg = try std.fmt.allocPrint(allocator, "{d}\n{s}\n", .{ self.counter, self.module_cid });
        defer allocator.free(msg);
        try file.writeAll(msg);
    }

    pub fn load(allocator: std.mem.Allocator, path: []const u8) !Baton {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const content = try file.readToEndAlloc(allocator, 1024);
        defer allocator.free(content);

        var it = std.mem.splitScalar(u8, content, '\n');
        const count_line = it.next() orelse return error.InvalidFormat;
        const cid_line = it.next() orelse return error.InvalidFormat;

        return Baton{
            .counter = try std.fmt.parseInt(i32, count_line, 10),
            .module_cid = try allocator.dupe(u8, cid_line),
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} [init|run]\n", .{args[0]});
        return;
    }

    if (std.mem.eql(u8, args[1], "init")) {
        const baton = Baton{ .counter = 0, .module_cid = "counter.wat" };
        try baton.save(allocator, "baton.txt");
        std.debug.print("Initialized baton.txt\n", .{});
    } else if (std.mem.eql(u8, args[1], "run")) {
        var baton = try Baton.load(allocator, "baton.txt");
        defer allocator.free(baton.module_cid);
        
        std.debug.print("Resuming Baton at counter {d}\n", .{baton.counter});

        const count_str = try std.fmt.allocPrint(allocator, "{d}", .{baton.counter});
        defer allocator.free(count_str);

        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "wasmtime", "run", "--invoke", "run_counter", baton.module_cid, count_str },
        });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.term == .Exited and result.term.Exited != 0) {
            std.debug.print("Wasmtime failed: {s}\n", .{result.stderr});
            return;
        }

        const output = std.mem.trim(u8, result.stdout, " \n\r");
        const next_counter = try std.fmt.parseInt(i32, output, 10);
        std.debug.print("Executed Wasm: count {d} -> {d}\n", .{baton.counter, next_counter});

        baton.counter = next_counter;
        try baton.save(allocator, "baton.txt");
        std.debug.print("Baton saved to baton.txt (next_counter={d})\n", .{next_counter});
    }
}
