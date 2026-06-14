// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// WASI check: verify that all listed .zig files are `zig fmt`-clean.
// This module compiles to wasm32-wasi and runs via:
//   wasmtime run --dir=. zig-out/lib/zig_fmt.wasm <file.zig> [file.zig...]
//
// Exit 0 = all files are formatted; 1 = at least one needs formatting or parse error.
// Unformatted file names are printed to stdout (one per line), errors to stderr.
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try std.fs.File.stderr().writeAll("usage: zig_fmt.wasm <file.zig> [file.zig...]\n");
        std.process.exit(1);
    }

    var all_ok = true;
    for (args[1..]) |path| {
        const ok = checkFile(allocator, path) catch |err| {
            const msg = try std.fmt.allocPrint(allocator, "zig_fmt: {s}: {s}\n", .{ path, @errorName(err) });
            defer allocator.free(msg);
            try std.fs.File.stderr().writeAll(msg);
            all_ok = false;
            continue;
        };
        if (!ok) {
            const msg = try std.fmt.allocPrint(allocator, "needs formatting: {s}\n", .{path});
            defer allocator.free(msg);
            try std.fs.File.stdout().writeAll(msg);
            all_ok = false;
        }
    }
    std.process.exit(if (all_ok) 0 else 1);
}

fn checkFile(allocator: std.mem.Allocator, path: []const u8) !bool {
    const source_raw = try std.fs.cwd().readFileAlloc(allocator, path, 1 * 1024 * 1024);
    defer allocator.free(source_raw);

    // Ast.parse requires a null-terminated source. Allocate a buffer with sentinel.
    const buf = try allocator.alloc(u8, source_raw.len + 1);
    defer allocator.free(buf);
    @memcpy(buf[0..source_raw.len], source_raw);
    buf[source_raw.len] = 0;
    const source: [:0]const u8 = buf[0..source_raw.len :0];

    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);

    if (tree.errors.len > 0) return false;

    const rendered = try tree.renderAlloc(allocator);
    defer allocator.free(rendered);

    return std.mem.eql(u8, source[0..source.len], rendered);
}
