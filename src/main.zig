// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
const std = @import("std");
const estate = @import("estate.zig");

pub const Baton = struct {
    counter: i32,
    module_cid: []const u8,
    guix_package: ?[]const u8 = null,
    required_cap: ?[]const u8 = null,

    pub fn save(self: Baton, allocator: std.mem.Allocator, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        const pkg = self.guix_package orelse "none";
        const cap = self.required_cap orelse "none";
        const msg = try std.fmt.allocPrint(allocator, "{d}\n{s}\n{s}\n{s}\n", .{ self.counter, self.module_cid, pkg, cap });
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
        const cap_line = it.next() orelse return error.InvalidFormat;

        return Baton{
            .counter = try std.fmt.parseInt(i32, count_line, 10),
            .module_cid = try allocator.dupe(u8, cid_line),
            .guix_package = if (std.mem.eql(u8, pkg_line, "none")) null else try allocator.dupe(u8, pkg_line),
            .required_cap = if (std.mem.eql(u8, cap_line, "none")) null else try allocator.dupe(u8, cap_line),
        };
    }
};

/// The verdict a CI-check Baton carries once it has been executed on a node.
/// `pending` = frozen before execution; `pass`/`fail` = the executed result.
pub const Verdict = enum {
    pending,
    pass,
    fail,

    pub fn fromString(s: []const u8) ?Verdict {
        if (std.mem.eql(u8, s, "pending")) return .pending;
        if (std.mem.eql(u8, s, "pass")) return .pass;
        if (std.mem.eql(u8, s, "fail")) return .fail;
        return null;
    }
};

/// A CI-check Baton: a mobile unit of CI work that names a check, declares the
/// capability a node must have to run it, and — once executed — freezes the
/// verdict so it can migrate to (and be consumed on) another node WITHOUT
/// re-running the check. This is the bag-of-actions answer to paid CI minutes:
/// the check runs on owned compute, and the verdict is the portable artifact.
pub const CheckBaton = struct {
    id: []const u8,
    check_id: []const u8,
    node: []const u8,
    required_cap: estate.Capability,
    verdict: Verdict,
    exit_code: i32,
    command: []const u8,
    digest: [64]u8 = [_]u8{'0'} ** 64,

    /// HMAC-SHA256 over the verdict-bearing fields, hex-encoded. Makes a frozen
    /// verdict tamper-evident: another node recomputes this with the shared key
    /// and rejects the Baton if it does not match. (Integrity/authenticity hook;
    /// the key comes from BAG_ATTEST_KEY — see `attestKey`.)
    pub fn digestHex(self: CheckBaton, allocator: std.mem.Allocator, key: []const u8) ![64]u8 {
        const canon = try std.fmt.allocPrint(
            allocator,
            "{s}|{s}|{s}|{s}|{s}|{d}|{s}",
            .{ self.id, self.check_id, self.node, @tagName(self.required_cap), @tagName(self.verdict), self.exit_code, self.command },
        );
        defer allocator.free(canon);

        const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
        var mac: [HmacSha256.mac_length]u8 = undefined;
        HmacSha256.create(&mac, canon, key);

        const hexchars = "0123456789abcdef";
        var hex: [64]u8 = undefined;
        for (mac, 0..) |byte, i| {
            hex[i * 2] = hexchars[byte >> 4];
            hex[i * 2 + 1] = hexchars[byte & 0x0f];
        }
        return hex;
    }

    /// Recompute the digest and compare it to the one carried in the envelope.
    pub fn verify(self: CheckBaton, allocator: std.mem.Allocator, key: []const u8) !bool {
        const expected = try self.digestHex(allocator, key);
        return std.mem.eql(u8, expected[0..], self.digest[0..]);
    }

    /// Freeze the Baton (incl. its verdict + attestation digest) to a versioned
    /// text envelope.
    pub fn freeze(self: CheckBaton, allocator: std.mem.Allocator, path: []const u8, key: []const u8) !void {
        const dh = try self.digestHex(allocator, key);
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        const msg = try std.fmt.allocPrint(
            allocator,
            "BAG-CHECK-BATON v1\nid={s}\ncheck_id={s}\nnode={s}\nrequired_cap={s}\nverdict={s}\nexit_code={d}\ncommand={s}\ndigest=hmac-sha256:{s}\n",
            .{ self.id, self.check_id, self.node, @tagName(self.required_cap), @tagName(self.verdict), self.exit_code, self.command, dh[0..] },
        );
        defer allocator.free(msg);
        try file.writeAll(msg);
    }

    /// Thaw a frozen Baton. All string fields are heap-owned — call `deinit`.
    pub fn thaw(allocator: std.mem.Allocator, path: []const u8) !CheckBaton {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const content = try file.readToEndAlloc(allocator, 8192);
        defer allocator.free(content);

        var b = CheckBaton{
            .id = try allocator.dupe(u8, ""),
            .check_id = try allocator.dupe(u8, ""),
            .node = try allocator.dupe(u8, ""),
            .required_cap = .linux,
            .verdict = .pending,
            .exit_code = 0,
            .command = try allocator.dupe(u8, ""),
        };

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const key = line[0..eq];
            const val = line[eq + 1 ..];
            if (std.mem.eql(u8, key, "id")) {
                allocator.free(b.id);
                b.id = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, key, "check_id")) {
                allocator.free(b.check_id);
                b.check_id = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, key, "node")) {
                allocator.free(b.node);
                b.node = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, key, "required_cap")) {
                b.required_cap = estate.Capability.fromString(val) orelse .linux;
            } else if (std.mem.eql(u8, key, "verdict")) {
                b.verdict = Verdict.fromString(val) orelse .pending;
            } else if (std.mem.eql(u8, key, "exit_code")) {
                b.exit_code = std.fmt.parseInt(i32, val, 10) catch 0;
            } else if (std.mem.eql(u8, key, "command")) {
                allocator.free(b.command);
                b.command = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, key, "digest")) {
                const hex = if (std.mem.startsWith(u8, val, "hmac-sha256:")) val["hmac-sha256:".len..] else val;
                const n = @min(hex.len, 64);
                @memcpy(b.digest[0..n], hex[0..n]);
            }
        }
        return b;
    }

    pub fn deinit(self: CheckBaton, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.check_id);
        allocator.free(self.node);
        allocator.free(self.command);
    }
};

/// The shared key used to attest frozen verdicts. Reads BAG_ATTEST_KEY; falls
/// back to a documented dev placeholder (integrity-only until a real key is set).
fn attestKey(allocator: std.mem.Allocator) ![]const u8 {
    return std.process.getEnvVarOwned(allocator, "BAG_ATTEST_KEY") catch
        try allocator.dupe(u8, "bag-of-actions-dev-key");
}

fn printOut(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const s = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(s);
    try std.fs.File.stdout().writeAll(s);
}

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
        std.debug.print("Usage: {s} [init|run|match|nodes|check|thaw]\n", .{args[0]});
        return;
    }

    if (std.mem.eql(u8, args[1], "nodes")) {
        // Print the estate node names from the single mirrored manifest.
        try estate.listNodeNames(std.fs.File.stdout());
        return;
    }

    if (std.mem.eql(u8, args[1], "init")) {
        const baton = Baton{ .counter = 0, .module_cid = "counter.wat", .guix_package = "hello", .required_cap = "guix" };
        try baton.save(allocator, "baton.txt");
        std.debug.print("Initialized baton.txt with Guix target 'hello'\n", .{});
    } else if (std.mem.eql(u8, args[1], "match")) {
        if (args.len < 3) {
            std.debug.print("Usage: {s} match <node_name> [required_caps...]\n", .{args[0]});
            return;
        }
        const node_name = args[2];
        const req_count = args.len - 3;
        const reqs = try allocator.alloc(estate.Capability, req_count);
        defer allocator.free(reqs);

        var valid_count: usize = 0;
        var has_unknown = false;
        for (args[3..]) |cap_str| {
            if (estate.Capability.fromString(cap_str)) |cap| {
                reqs[valid_count] = cap;
                valid_count += 1;
            } else {
                // An unknown/unprovable requirement can NEVER be satisfied.
                has_unknown = true;
            }
        }

        if (!has_unknown and estate.nodeSatisfies(node_name, reqs[0..valid_count])) {
            std.debug.print("MATCH: TRUE\n", .{});
            std.process.exit(0);
        } else {
            std.debug.print("MATCH: FALSE\n", .{});
            std.process.exit(1);
        }
    } else if (std.mem.eql(u8, args[1], "check")) {
        // bag_of_actions check <node> <cap> <check_id> <freeze_path> <cmd> [args...]
        // Run an estate CI check as a Baton on a capability-matched node, then
        // freeze the verdict. Exit 0 = pass, 1 = fail, 2 = no capable node.
        if (args.len < 7) {
            std.debug.print("Usage: {s} check <node> <cap> <check_id> <freeze_path> <cmd> [args...]\n", .{args[0]});
            std.process.exit(64);
        }
        const node = args[2];
        const cap = estate.Capability.fromString(args[3]) orelse {
            std.debug.print("Unknown capability: {s}\n", .{args[3]});
            std.process.exit(64);
        };
        const check_id = args[4];
        const freeze_path = args[5];
        const cmd_argv = args[6..];

        const key = try attestKey(allocator);
        defer allocator.free(key);

        // 1. Capability gate: only run on a node that satisfies the requirement.
        if (!estate.nodeSatisfies(node, &[_]estate.Capability{cap})) {
            try printOut(allocator, "VERDICT=suspended\nReason: node '{s}' lacks capability '{s}'. Work suspended (no minutes burned).\n", .{ node, @tagName(cap) });
            // Freeze a pending Baton so the work can migrate to a capable node.
            const joined = try std.mem.join(allocator, " ", cmd_argv);
            defer allocator.free(joined);
            const baton = CheckBaton{ .id = check_id, .check_id = check_id, .node = node, .required_cap = cap, .verdict = .pending, .exit_code = -1, .command = joined };
            try baton.freeze(allocator, freeze_path, key);
            std.process.exit(2);
        }

        // 2. Execute the real check on this (capable) node.
        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = cmd_argv,
        });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        const code: i32 = switch (result.term) {
            .Exited => |c| @intCast(c),
            else => 1,
        };
        const verdict: Verdict = if (code == 0) .pass else .fail;

        // 3. Freeze the verdict — the portable artifact that replaces a paid run.
        const joined = try std.mem.join(allocator, " ", cmd_argv);
        defer allocator.free(joined);
        const baton = CheckBaton{ .id = check_id, .check_id = check_id, .node = node, .required_cap = cap, .verdict = verdict, .exit_code = code, .command = joined };
        try baton.freeze(allocator, freeze_path, key);

        try printOut(allocator, "VERDICT={s}\ncheck_id={s} node={s} cap={s} exit_code={d}\nFrozen+attested to {s} (0 GitHub minutes)\n", .{ @tagName(verdict), check_id, node, @tagName(cap), code, freeze_path });
        std.process.exit(if (verdict == .pass) 0 else 1);
    } else if (std.mem.eql(u8, args[1], "thaw")) {
        // bag_of_actions thaw <freeze_path>
        // Consume a frozen verdict on another node — zero re-execution.
        if (args.len < 3) {
            std.debug.print("Usage: {s} thaw <freeze_path>\n", .{args[0]});
            std.process.exit(64);
        }
        var baton = try CheckBaton.thaw(allocator, args[2]);
        defer baton.deinit(allocator);

        const key = try attestKey(allocator);
        defer allocator.free(key);
        if (!try baton.verify(allocator, key)) {
            try printOut(allocator, "VERDICT=tampered\ncheck_id={s}: attestation digest does not match — verdict REJECTED.\n", .{baton.check_id});
            std.process.exit(3);
        }

        try printOut(allocator, "VERDICT={s}\ncheck_id={s} node={s} cap={s} exit_code={d}\ncommand={s}\nattestation=verified\n", .{ @tagName(baton.verdict), baton.check_id, baton.node, @tagName(baton.required_cap), baton.exit_code, baton.command });
        std.process.exit(if (baton.verdict == .pass) 0 else 1);
    } else if (std.mem.eql(u8, args[1], "run")) {
        var baton = try Baton.load(allocator, "baton.txt");
        defer allocator.free(baton.module_cid);
        defer if (baton.guix_package) |pkg| allocator.free(pkg);
        defer if (baton.required_cap) |cap| allocator.free(cap);

        std.debug.print("Resuming Baton [Counter: {d}, Module: {s}]\n", .{ baton.counter, baton.module_cid });

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
        std.debug.print("Wasm State Update: {d} -> {d}\n", .{ baton.counter, next_counter });

        baton.counter = next_counter;
        try baton.save(allocator, "baton.txt");
        std.debug.print("Baton cycle complete. Saved for next node.\n", .{});
    }
}

test "CheckBaton freeze/thaw round-trips the verdict and verifies attestation" {
    const a = std.testing.allocator;
    const key = "test-key";
    const original = CheckBaton{
        .id = "cib-001",
        .check_id = "zig-fmt-check",
        .node = "mesh-server-1",
        .required_cap = .zig,
        .verdict = .pass,
        .exit_code = 0,
        .command = "zig fmt --check build.zig",
    };
    const path = "test-ci-baton-roundtrip.txt";
    try original.freeze(a, path, key);
    defer std.fs.cwd().deleteFile(path) catch {};

    var thawed = try CheckBaton.thaw(a, path);
    defer thawed.deinit(a);

    try std.testing.expectEqualStrings(original.id, thawed.id);
    try std.testing.expectEqualStrings(original.check_id, thawed.check_id);
    try std.testing.expectEqualStrings(original.node, thawed.node);
    try std.testing.expectEqualStrings(original.command, thawed.command);
    try std.testing.expect(original.required_cap == thawed.required_cap);
    try std.testing.expect(original.verdict == thawed.verdict);
    try std.testing.expect(original.exit_code == thawed.exit_code);
    try std.testing.expect(try thawed.verify(a, key));
}

test "CheckBaton preserves a fail verdict and nonzero exit code" {
    const a = std.testing.allocator;
    const original = CheckBaton{
        .id = "cib-002",
        .check_id = "zig-fmt-check",
        .node = "mesh-server-1",
        .required_cap = .zig,
        .verdict = .fail,
        .exit_code = 1,
        .command = "zig fmt --check src/main.zig",
    };
    const path = "test-ci-baton-fail.txt";
    try original.freeze(a, path, "test-key");
    defer std.fs.cwd().deleteFile(path) catch {};

    var thawed = try CheckBaton.thaw(a, path);
    defer thawed.deinit(a);

    try std.testing.expect(thawed.verdict == .fail);
    try std.testing.expect(thawed.exit_code == 1);
}

test "attestation detects a tampered verdict" {
    const a = std.testing.allocator;
    const key = "test-key";
    const original = CheckBaton{
        .id = "cib-003",
        .check_id = "zig-fmt-check",
        .node = "mesh-server-1",
        .required_cap = .zig,
        .verdict = .fail,
        .exit_code = 1,
        .command = "zig fmt --check src/main.zig",
    };
    const path = "test-ci-baton-tamper.txt";
    try original.freeze(a, path, key);
    defer std.fs.cwd().deleteFile(path) catch {};

    // Forge a pass verdict in the frozen envelope without re-attesting.
    const content = blk: {
        const rf = try std.fs.cwd().openFile(path, .{});
        defer rf.close();
        break :blk try rf.readToEndAlloc(a, 8192);
    };
    defer a.free(content);
    const forged = try std.mem.replaceOwned(u8, a, content, "verdict=fail", "verdict=pass");
    defer a.free(forged);
    {
        const f = try std.fs.cwd().createFile(path, .{});
        defer f.close();
        try f.writeAll(forged);
    }

    var thawed = try CheckBaton.thaw(a, path);
    defer thawed.deinit(a);
    try std.testing.expect(thawed.verdict == .pass); // the forged value parsed...
    try std.testing.expect(!try thawed.verify(a, key)); // ...but attestation rejects it.
}

test "attestation with the wrong key fails verification" {
    const a = std.testing.allocator;
    const original = CheckBaton{
        .id = "cib-004",
        .check_id = "zig-fmt-check",
        .node = "mesh-server-1",
        .required_cap = .zig,
        .verdict = .pass,
        .exit_code = 0,
        .command = "zig fmt --check build.zig",
    };
    const path = "test-ci-baton-wrongkey.txt";
    try original.freeze(a, path, "key-a");
    defer std.fs.cwd().deleteFile(path) catch {};

    var thawed = try CheckBaton.thaw(a, path);
    defer thawed.deinit(a);
    try std.testing.expect(try thawed.verify(a, "key-a"));
    try std.testing.expect(!try thawed.verify(a, "key-b"));
}

test "Verdict.fromString parses known tags and rejects unknown" {
    try std.testing.expect(Verdict.fromString("pass").? == .pass);
    try std.testing.expect(Verdict.fromString("fail").? == .fail);
    try std.testing.expect(Verdict.fromString("pending").? == .pending);
    try std.testing.expect(Verdict.fromString("bogus") == null);
}
