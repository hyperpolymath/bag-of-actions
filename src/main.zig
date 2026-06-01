// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
const std = @import("std");

pub const Baton = struct {
    counter: i32,
    module_cid: []const u8,
    guix_package: ?[]const u8 = null,

    pub fn save(self: Baton, allocator: std.mem.Allocator, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        const pkg = self.guix_package orelse "none";
        const msg = try std.fmt.allocPrint(allocator, "{d}\n{s}\n{s}\n", .{ self.counter, self.module_cid, pkg });
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
        const pkg_line = it.next() orelse return error.InvalidFormat;

        return Baton{
            .counter = try std.fmt.parseInt(i32, count_line, 10),
            .module_cid = try allocator.dupe(u8, cid_line),
            .guix_package = if (std.mem.eql(u8, pkg_line, "none")) null else try allocator.dupe(u8, pkg_line),
        };
    }
};

fn runGuixBuild(allocator: std.mem.Allocator, package: []const u8) ![]const u8 {
    std.debug.print("Guix Policy: Orchestrating build for {s}\n", .{package});
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "guix", "build", package },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term == .Exited and result.term.Exited == 0) {
        const store_path = try allocator.dupe(u8, std.mem.trim(u8, result.stdout, " \n\r"));
        std.debug.print("Guix Success: {s}\n", .{store_path});
        return store_path;
    } else {
        std.debug.print("Guix Error: {s}\n", .{result.stderr});
        return error.GuixBuildFailed;
    }
}

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
        const baton = Baton{ .counter = 0, .module_cid = "counter.wat", .guix_package = "hello" };
        try baton.save(allocator, "baton.txt");
        std.debug.print("Initialized baton.txt with Guix target 'hello'\n", .{});
    } else if (std.mem.eql(u8, args[1], "run")) {
        var baton = try Baton.load(allocator, "baton.txt");
        defer allocator.free(baton.module_cid);
        defer if (baton.guix_package) |pkg| allocator.free(pkg);
        
        std.debug.print("Resuming Baton [Counter: {d}, Module: {s}]\n", .{baton.counter, baton.module_cid});

        // Step 1: Pre-execution Guix Action (Real World FFI simulation)
        if (baton.counter == 0) {
            if (baton.guix_package) |pkg| {
                const store_path = try runGuixBuild(allocator, pkg);
                defer allocator.free(store_path);
                std.debug.print("Artifact verified at {s}. Proceeding to Wasm transition.\n", .{store_path});
            }
        }

        // Step 2: Wasm Transition
        const count_str = try std.fmt.allocPrint(allocator, "{d}", .{baton.counter});
        defer allocator.free(count_str);

        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{ "wasmtime", "run", "--invoke", "run_counter", baton.module_cid, count_str },
        });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.term == .Exited and result.term.Exited != 0) {
            std.debug.print("Wasm Transition Failed: {s}\n", .{result.stderr});
            return;
        }

        const output = std.mem.trim(u8, result.stdout, " \n\r");
        const next_counter = try std.fmt.parseInt(i32, output, 10);
        std.debug.print("Wasm State Update: {d} -> {d}\n", .{baton.counter, next_counter});

        baton.counter = next_counter;
        try baton.save(allocator, "baton.txt");
        std.debug.print("Baton cycle complete. Saved for next node.\n", .{});
    }
}
