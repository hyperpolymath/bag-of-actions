// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//! Crash-safe file persistence helpers. `atomicWrite` guarantees that a reader
//! ever sees either the old file or the fully-written new file — never a
//! truncated/partial one — even if the process or host crashes mid-write.
const std = @import("std");

/// Atomically replace `path` with `bytes`.
///
/// Strategy (POSIX durable-rename pattern):
///   1. write the payload to a sibling temp file `<path>.tmp.<pid>`,
///   2. fsync that file so its data hits stable storage,
///   3. rename it over `path` (atomic on POSIX — readers see old or new, never partial),
///   4. fsync the parent directory so the rename entry itself is durable.
///
/// Steps 1–3 are required for correctness; the dir fsync (4) is best-effort —
/// if the parent directory cannot be opened we proceed without it rather than fail.
pub fn atomicWrite(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) !void {
    const pid = std.os.linux.getpid();
    const tmp_path = try std.fmt.allocPrint(allocator, "{s}.tmp.{d}", .{ path, pid });
    defer allocator.free(tmp_path);

    // On any failure before the rename succeeds, clean up the temp file.
    var renamed = false;
    errdefer if (!renamed) std.fs.cwd().deleteFile(tmp_path) catch {};

    {
        const tmp = try std.fs.cwd().createFile(tmp_path, .{ .truncate = true });
        defer tmp.close();
        try tmp.writeAll(bytes);
        try tmp.sync(); // fsync the data before exposing it via rename
    }

    try std.fs.cwd().rename(tmp_path, path);
    renamed = true;

    // Best-effort: fsync the parent directory so the rename survives a crash.
    // Use the raw syscall and ignore errno: some filesystems (e.g. the WSL 9p
    // overlay) reject directory fsync with EINVAL, which std.posix.fsync would
    // turn into an `unreachable` panic. Durability here is a bonus, not required.
    const dir_path = std.fs.path.dirname(path) orelse ".";
    if (std.fs.cwd().openDir(dir_path, .{})) |dir| {
        var d = dir;
        defer d.close();
        _ = std.os.linux.fsync(d.fd);
    } else |_| {}
}

// ── Tests ──────────────────────────────────────────────────────────────────────

test "atomicWrite round-trips and overwrites" {
    const a = std.testing.allocator;
    const path = "test-store-atomic.txt";
    defer std.fs.cwd().deleteFile(path) catch {};

    // First write creates the file.
    try atomicWrite(a, path, "first payload\n");
    {
        const got = try std.fs.cwd().readFileAlloc(a, path, 4096);
        defer a.free(got);
        try std.testing.expectEqualStrings("first payload\n", got);
    }

    // Second write atomically overwrites it.
    try atomicWrite(a, path, "second longer payload\n");
    {
        const got = try std.fs.cwd().readFileAlloc(a, path, 4096);
        defer a.free(got);
        try std.testing.expectEqualStrings("second longer payload\n", got);
    }

    // No temp file should be left behind.
    const pid = std.os.linux.getpid();
    const tmp_path = try std.fmt.allocPrint(a, "{s}.tmp.{d}", .{ path, pid });
    defer a.free(tmp_path);
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access(tmp_path, .{}));
}
