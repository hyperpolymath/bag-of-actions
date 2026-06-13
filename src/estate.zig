// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
const std = @import("std");

/// Mapping to Idris 2 Bag.Protocol.Capability tags (capToTag). Kept in step with
/// verification/proofs/Bag/Protocol.idr — add a capability in BOTH or neither.
pub const Capability = enum(u32) {
    linux = 1,
    macos = 2,
    gpu = 3,
    guix = 4,
    trusted_host = 5,
    secret_access = 6,
    zig = 7,
    rust = 8,
    cargo = 9,
    deno = 10,

    pub fn fromString(s: []const u8) ?Capability {
        if (std.mem.eql(u8, s, "linux")) return .linux;
        if (std.mem.eql(u8, s, "macos")) return .macos;
        if (std.mem.eql(u8, s, "gpu")) return .gpu;
        if (std.mem.eql(u8, s, "guix")) return .guix;
        if (std.mem.eql(u8, s, "trusted_host")) return .trusted_host;
        if (std.mem.eql(u8, s, "secret_access")) return .secret_access;
        if (std.mem.eql(u8, s, "zig")) return .zig;
        if (std.mem.eql(u8, s, "rust")) return .rust;
        if (std.mem.eql(u8, s, "cargo")) return .cargo;
        if (std.mem.eql(u8, s, "deno")) return .deno;
        return null;
    }
};

pub const Node = struct {
    name: []const u8,
    capabilities: []const Capability,
    /// Tropical (min-plus) money grade of running a unit of work here. Owned
    /// nodes ≈ free; the github-runner is the paid route. Mirrors Estate.idr.
    cost: u32,
};

/// The Estate Manifest (Hand-translated from verification/proofs/Bag/Estate.idr)
pub const estate = [_]Node{
    .{
        .name = "mesh-laptop",
        .capabilities = &[_]Capability{ .macos, .guix, .trusted_host, .zig },
        .cost = 2,
    },
    .{
        .name = "mesh-server-1",
        .capabilities = &[_]Capability{ .linux, .gpu, .guix, .trusted_host, .zig, .rust, .cargo, .deno },
        .cost = 1,
    },
    .{
        .name = "mesh-github-runner",
        .capabilities = &[_]Capability{ .linux, .secret_access },
        .cost = 100,
    },
};

pub fn findNode(name: []const u8) ?Node {
    for (estate) |node| {
        if (std.mem.eql(u8, node.name, name)) return node;
    }
    return null;
}

pub fn nodeSatisfies(node_name: []const u8, requirements: []const Capability) bool {
    const node = findNode(node_name) orelse return false;
    
    for (requirements) |req| {
        var found = false;
        for (node.capabilities) |cap| {
            if (cap == req) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}
