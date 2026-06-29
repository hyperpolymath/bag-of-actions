// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
const std = @import("std");
const estate = @import("estate.zig");
const crypto = @import("crypto.zig");
const store = @import("store.zig");

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

/// Hex-encoded ed25519 signature + signing public key produced by `signEd25519WithSeed`.
const Ed25519Result = struct { sig: [128]u8, pubkey: [64]u8 };

/// A CI-check Baton: a mobile unit of CI work that names a check, declares the
/// capability a node must have to run it, and — once executed — freezes the
/// verdict so it can migrate to (and be consumed on) another node WITHOUT
/// re-running the check. This is the bag-of-actions answer to paid CI minutes:
/// the check runs on owned compute, and the verdict is the portable artifact.
///
/// Attestation layers:
///   1. HMAC-SHA256 (shared key, BAG_ATTEST_KEY): integrity-evident.
///   2. ed25519 (per-node private key, BAG_SIGN_KEY_PATH): authenticity-evident.
///      Only the private-key holder can produce a valid ed25519 signature;
///      thaw verifies both layers and rejects if either fails.
///      Old envelopes without the ed25519 fields remain fully valid (backward compat).
///
/// Optional artifact support: if the check writes a report file (e.g. a Scorecard
/// JSON result), set `artifact_path` and `artifact_sha256`. The sha256 is included
/// in both HMAC and ed25519 canonical strings, binding the report to the Baton.
pub const CheckBaton = struct {
    id: []const u8,
    check_id: []const u8,
    node: []const u8,
    required_cap: estate.Capability,
    verdict: Verdict,
    exit_code: i32,
    command: []const u8,
    digest: [64]u8 = [_]u8{'0'} ** 64,
    /// Attestation mode this verdict was frozen under (BAG_MODE; default "prod").
    /// Bound into the canonical string so it cannot be edited after freezing, and
    /// surfaced on thaw so the GitHub bridge can refuse to green a non-prod verdict.
    mode: []const u8 = "prod",
    /// Identifier of the HMAC key used (BAG_ATTEST_KEY_ID; default "default").
    /// Bound into the canonical string and used by thaw to select the verifying
    /// key from the keyring, enabling overlap-window key rotation.
    key_id: []const u8 = "default",
    /// Envelope format version parsed from the header line. In-memory batons are
    /// v2; a thawed v1 / unversioned envelope is rejected by `checkAttestation`.
    version: u8 = 2,
    /// Path where the check wrote its report (metadata only — not attested directly).
    artifact_path: ?[]const u8 = null,
    /// Hex-encoded SHA-256 of the artifact file. Included in both HMAC and ed25519
    /// canonical strings when non-null; tampering with the report is detected on thaw.
    artifact_sha256: ?[64]u8 = null,
    /// Hex-encoded ed25519 signature (64 bytes → 128 hex chars). Produced by the
    /// executing node's private key (BAG_SIGN_KEY_PATH / ~/.ssh/id_ed25519_signing).
    /// Makes the frozen verdict authenticity-evident in addition to HMAC integrity.
    /// Absent on Batons from nodes without a signing key — thaw accepts both cases.
    signature: ?[128]u8 = null,
    /// Hex-encoded raw ed25519 public key of the signer (32 bytes → 64 hex chars).
    /// Self-contained: verifiers do not need an out-of-band key lookup.
    signing_pubkey: ?[64]u8 = null,
    /// Path to the WASI module that executed this check (metadata — not attested inline).
    wasm_path: ?[]const u8 = null,
    /// Hex-encoded SHA-256 of the WASI module binary. Included in canonical string when
    /// non-null so tampering with the module is detected on thaw.
    wasm_digest: ?[64]u8 = null,
    /// Tool version string (e.g., "scorecard 5.1.0") from BAG_TOOL_VERSION.
    /// Included in canonical string when non-null — binds the version to the verdict.
    tool_version: ?[]const u8 = null,
    /// Small artifact inlined as standard base64 (file ≤ BAG_ARTIFACT_INLINE_MAX bytes).
    /// Allows consumers to inspect the report without a separate file transfer.
    artifact_inline_b64: ?[]const u8 = null,

    /// Build the canonical string that both HMAC and ed25519 sign over.
    /// Optional extensions are appended in a defined order; absent fields are omitted
    /// so old envelopes (which lack later extensions) remain valid.
    /// Format: id|check_id|node|cap|verdict|exit|cmd|mode:M|kid:K[|sha256][|wasm:wasm_sha256][|tv:version]
    /// `mode` and `kid` are mandatory in v2, so a v1 envelope (which lacks them)
    /// can never produce a matching digest — dropping v1 acceptance cryptographically.
    pub fn canonicalString(self: CheckBaton, allocator: std.mem.Allocator) ![]u8 {
        var s = try std.fmt.allocPrint(
            allocator,
            "{s}|{s}|{s}|{s}|{s}|{d}|{s}|mode:{s}|kid:{s}",
            .{ self.id, self.check_id, self.node, @tagName(self.required_cap), @tagName(self.verdict), self.exit_code, self.command, self.mode, self.key_id },
        );
        if (self.artifact_sha256) |sha| {
            const prev = s;
            s = try std.fmt.allocPrint(allocator, "{s}|{s}", .{ prev, sha[0..] });
            allocator.free(prev);
        }
        if (self.wasm_digest) |wd| {
            const prev = s;
            s = try std.fmt.allocPrint(allocator, "{s}|wasm:{s}", .{ prev, wd[0..] });
            allocator.free(prev);
        }
        if (self.tool_version) |tv| {
            const prev = s;
            s = try std.fmt.allocPrint(allocator, "{s}|tv:{s}", .{ prev, tv });
            allocator.free(prev);
        }
        return s;
    }

    /// HMAC-SHA256 over the canonical string, hex-encoded.
    pub fn digestHex(self: CheckBaton, allocator: std.mem.Allocator, key: []const u8) ![64]u8 {
        const canon = try self.canonicalString(allocator);
        defer allocator.free(canon);

        const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
        var mac: [HmacSha256.mac_length]u8 = undefined;
        HmacSha256.create(&mac, canon, key);

        return crypto.bytesToHex(HmacSha256.mac_length, mac);
    }

    /// Recompute the HMAC digest and compare it to the one in the envelope.
    pub fn verify(self: CheckBaton, allocator: std.mem.Allocator, key: []const u8) !bool {
        const expected = try self.digestHex(allocator, key);
        return std.mem.eql(u8, expected[0..], self.digest[0..]);
    }

    /// Sign the canonical string with the given 32-byte ed25519 seed.
    /// Returns hex-encoded (signature, public-key) pair.
    pub fn signEd25519WithSeed(self: CheckBaton, allocator: std.mem.Allocator, seed: [32]u8) !Ed25519Result {
        const canon = try self.canonicalString(allocator);
        defer allocator.free(canon);

        const Ed25519 = std.crypto.sign.Ed25519;
        const kp = try Ed25519.KeyPair.generateDeterministic(seed);
        const sig = try kp.sign(canon, null); // null noise = deterministic
        const sig_bytes = sig.toBytes();
        const pk_bytes = kp.public_key.toBytes();

        return .{
            .sig = crypto.bytesToHex(sig_bytes.len, sig_bytes),
            .pubkey = crypto.bytesToHex(pk_bytes.len, pk_bytes),
        };
    }

    /// Sign the canonical string using the OpenSSH private key at `key_path`.
    /// Defaults to BAG_SIGN_KEY_PATH, falling back to ~/.ssh/id_ed25519_signing.
    /// Key must be unencrypted ed25519 (the estate signing key, NOT the auth key).
    pub fn signEd25519(self: CheckBaton, allocator: std.mem.Allocator, key_path: []const u8) !Ed25519Result {
        const seed = try crypto.readEd25519Seed(allocator, key_path);
        return self.signEd25519WithSeed(allocator, seed);
    }

    /// Verify the ed25519 signature carried in this Baton against its stored public key.
    /// Returns `false` (not an error) if no signature is present — caller decides policy.
    /// Returns `false` on invalid signature or malformed fields.
    pub fn verifyEd25519(self: CheckBaton, allocator: std.mem.Allocator) !bool {
        const sig_hex = self.signature orelse return false;
        const pk_hex = self.signing_pubkey orelse return false;

        var sig_bytes: [64]u8 = undefined;
        crypto.hexDecode(&sig_bytes, sig_hex[0..]) catch return false;
        var pk_bytes: [32]u8 = undefined;
        crypto.hexDecode(&pk_bytes, pk_hex[0..]) catch return false;

        const canon = try self.canonicalString(allocator);
        defer allocator.free(canon);

        const Ed25519 = std.crypto.sign.Ed25519;
        const pk = Ed25519.PublicKey.fromBytes(pk_bytes) catch return false;
        const sig = Ed25519.Signature.fromBytes(sig_bytes);
        sig.verify(canon, pk) catch return false;
        return true;
    }

    /// Outcome of the full fail-closed attestation check applied on thaw.
    pub const AttestResult = enum { ok, bad_version, bad_hmac, missing_sig, bad_sig };

    /// Fail-closed attestation gate used on thaw: the envelope MUST be v2,
    /// HMAC-valid under `key`, carry an ed25519 signature, and that signature MUST
    /// verify. Any shortfall returns a specific non-`ok` result — never a soft pass.
    /// This is the runtime end of "every envelope is v2 + ed25519-mandatory": an
    /// unsigned or HMAC-only envelope can no longer discharge a verdict.
    pub fn checkAttestation(self: CheckBaton, allocator: std.mem.Allocator, key: []const u8) !AttestResult {
        if (self.version != 2) return .bad_version;
        if (!try self.verify(allocator, key)) return .bad_hmac;
        if (self.signature == null or self.signing_pubkey == null) return .missing_sig;
        if (!try self.verifyEd25519(allocator)) return .bad_sig;
        return .ok;
    }

    /// Freeze the Baton (verdict + HMAC + optional ed25519 signature) to a versioned
    /// text envelope. Fields are appended in order so parsers that stop at `digest`
    /// remain compatible with older envelopes.
    pub fn freeze(self: CheckBaton, allocator: std.mem.Allocator, path: []const u8, key: []const u8) !void {
        const dh = try self.digestHex(allocator, key);
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        const base = try std.fmt.allocPrint(
            allocator,
            "BAG-CHECK-BATON v2\nid={s}\ncheck_id={s}\nnode={s}\nrequired_cap={s}\nmode={s}\nkey_id={s}\nverdict={s}\nexit_code={d}\ncommand={s}\ndigest=hmac-sha256:{s}\n",
            .{ self.id, self.check_id, self.node, @tagName(self.required_cap), self.mode, self.key_id, @tagName(self.verdict), self.exit_code, self.command, dh[0..] },
        );
        defer allocator.free(base);
        try file.writeAll(base);
        if (self.artifact_path) |ap| {
            const line = try std.fmt.allocPrint(allocator, "artifact_path={s}\n", .{ap});
            defer allocator.free(line);
            try file.writeAll(line);
        }
        if (self.artifact_sha256) |sha| {
            const line = try std.fmt.allocPrint(allocator, "artifact_sha256={s}\n", .{sha[0..]});
            defer allocator.free(line);
            try file.writeAll(line);
        }
        if (self.signature) |sig| {
            const line = try std.fmt.allocPrint(allocator, "signature=ed25519:{s}\n", .{sig[0..]});
            defer allocator.free(line);
            try file.writeAll(line);
        }
        if (self.signing_pubkey) |pk| {
            const line = try std.fmt.allocPrint(allocator, "signing_pubkey={s}\n", .{pk[0..]});
            defer allocator.free(line);
            try file.writeAll(line);
        }
        if (self.wasm_path) |wp| {
            const line = try std.fmt.allocPrint(allocator, "wasm_path={s}\n", .{wp});
            defer allocator.free(line);
            try file.writeAll(line);
        }
        if (self.wasm_digest) |wd| {
            const line = try std.fmt.allocPrint(allocator, "wasm_digest={s}\n", .{wd[0..]});
            defer allocator.free(line);
            try file.writeAll(line);
        }
        if (self.tool_version) |tv| {
            const line = try std.fmt.allocPrint(allocator, "tool_version={s}\n", .{tv});
            defer allocator.free(line);
            try file.writeAll(line);
        }
        if (self.artifact_inline_b64) |b64| {
            const line = try std.fmt.allocPrint(allocator, "artifact_inline_b64={s}\n", .{b64});
            defer allocator.free(line);
            try file.writeAll(line);
        }
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
            .mode = try allocator.dupe(u8, "prod"),
            .key_id = try allocator.dupe(u8, "default"),
            .version = 0, // unknown until the header line is parsed
        };

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            // Header line carries the envelope version; v1/unversioned ⇒ version 0/1,
            // which checkAttestation rejects (and whose canonical string can't match).
            if (std.mem.startsWith(u8, line, "BAG-CHECK-BATON v")) {
                const vs = std.mem.trim(u8, line["BAG-CHECK-BATON v".len..], " \r\t");
                b.version = std.fmt.parseInt(u8, vs, 10) catch 0;
                continue;
            }
            const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const k = line[0..eq];
            const val = line[eq + 1 ..];
            if (std.mem.eql(u8, k, "id")) {
                allocator.free(b.id);
                b.id = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, k, "check_id")) {
                allocator.free(b.check_id);
                b.check_id = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, k, "node")) {
                allocator.free(b.node);
                b.node = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, k, "required_cap")) {
                b.required_cap = estate.Capability.fromString(val) orelse .linux;
            } else if (std.mem.eql(u8, k, "verdict")) {
                b.verdict = Verdict.fromString(val) orelse .pending;
            } else if (std.mem.eql(u8, k, "exit_code")) {
                b.exit_code = std.fmt.parseInt(i32, val, 10) catch 0;
            } else if (std.mem.eql(u8, k, "command")) {
                allocator.free(b.command);
                b.command = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, k, "mode")) {
                allocator.free(b.mode);
                b.mode = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, k, "key_id")) {
                allocator.free(b.key_id);
                b.key_id = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, k, "digest")) {
                const hex = if (std.mem.startsWith(u8, val, "hmac-sha256:")) val["hmac-sha256:".len..] else val;
                const n = @min(hex.len, 64);
                @memcpy(b.digest[0..n], hex[0..n]);
            } else if (std.mem.eql(u8, k, "artifact_path")) {
                if (b.artifact_path) |old| allocator.free(old);
                b.artifact_path = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, k, "artifact_sha256")) {
                var sha: [64]u8 = undefined;
                const n = @min(val.len, 64);
                @memcpy(sha[0..n], val[0..n]);
                if (n < 64) @memset(sha[n..], '0');
                b.artifact_sha256 = sha;
            } else if (std.mem.eql(u8, k, "signature")) {
                const hex = if (std.mem.startsWith(u8, val, "ed25519:")) val["ed25519:".len..] else val;
                if (hex.len == 128) {
                    var sig: [128]u8 = undefined;
                    @memcpy(&sig, hex[0..128]);
                    b.signature = sig;
                }
            } else if (std.mem.eql(u8, k, "signing_pubkey")) {
                if (val.len == 64) {
                    var pk: [64]u8 = undefined;
                    @memcpy(&pk, val[0..64]);
                    b.signing_pubkey = pk;
                }
            } else if (std.mem.eql(u8, k, "wasm_path")) {
                if (b.wasm_path) |old| allocator.free(old);
                b.wasm_path = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, k, "wasm_digest")) {
                if (val.len == 64) {
                    var wd: [64]u8 = undefined;
                    @memcpy(&wd, val[0..64]);
                    b.wasm_digest = wd;
                }
            } else if (std.mem.eql(u8, k, "tool_version")) {
                if (b.tool_version) |old| allocator.free(old);
                b.tool_version = try allocator.dupe(u8, val);
            } else if (std.mem.eql(u8, k, "artifact_inline_b64")) {
                if (b.artifact_inline_b64) |old| allocator.free(old);
                b.artifact_inline_b64 = try allocator.dupe(u8, val);
            }
        }
        return b;
    }

    pub fn deinit(self: CheckBaton, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.check_id);
        allocator.free(self.node);
        allocator.free(self.command);
        allocator.free(self.mode);
        allocator.free(self.key_id);
        if (self.artifact_path) |ap| allocator.free(ap);
        if (self.wasm_path) |wp| allocator.free(wp);
        if (self.tool_version) |tv| allocator.free(tv);
        if (self.artifact_inline_b64) |b64| allocator.free(b64);
    }
};

/// Parse an SSH ed25519 public key file (.pub) and return the 32-byte raw key.
fn readEd25519Pubkey(allocator: std.mem.Allocator, path: []const u8) ![32]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const content = try file.readToEndAlloc(allocator, 4096);
    defer allocator.free(content);

    // Format: "ssh-ed25519 <base64-blob> [comment]"
    const trimmed = std.mem.trim(u8, content, " \r\n\t");
    var parts = std.mem.splitScalar(u8, trimmed, ' ');
    const keytype = parts.next() orelse return error.InvalidPubkeyFormat;
    if (!std.mem.eql(u8, keytype, "ssh-ed25519")) return error.NotEd25519Pubkey;
    const b64 = parts.next() orelse return error.InvalidPubkeyFormat;

    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(b64) catch return error.InvalidPubkeyFormat;
    const decoded = try allocator.alloc(u8, decoded_len);
    defer allocator.free(decoded);
    try std.base64.standard.Decoder.decode(decoded, b64);

    // blob: 4-byte type-len + "ssh-ed25519" + 4-byte key-len (32) + 32-byte key.
    var pos: usize = 0;
    if (pos + 4 > decoded.len) return error.InvalidPubkeyFormat;
    const type_len = std.mem.readInt(u32, decoded[pos..][0..4], .big);
    pos += 4;
    if (pos + type_len > decoded.len) return error.InvalidPubkeyFormat;
    pos += type_len; // skip "ssh-ed25519"
    if (pos + 4 > decoded.len) return error.InvalidPubkeyFormat;
    const key_len = std.mem.readInt(u32, decoded[pos..][0..4], .big);
    pos += 4;
    if (key_len != 32 or pos + 32 > decoded.len) return error.InvalidPubkeyFormat;

    var pubkey: [32]u8 = undefined;
    @memcpy(&pubkey, decoded[pos..][0..32]);
    return pubkey;
}

/// Minimum acceptable length of a real shared HMAC key. Anything shorter is
/// treated as unconfigured (the old dev placeholder was 20 bytes).
const min_attest_key_len = 32;

/// EX_CONFIG: the conventional sysexits.h code for a configuration error. Used
/// for every fail-closed refusal so callers can distinguish "misconfigured" (78)
/// from "tampered verdict" (3) and "honest fail" (1).
const ex_config = 78;

/// The active HMAC key for FREEZING. Fail-closed: requires BAG_ATTEST_KEY present
/// and >= 32 bytes — there is NO dev-key fallback. A node that cannot prove it has
/// a real shared secret must not attest anything.
fn activeAttestKey(allocator: std.mem.Allocator) ![]const u8 {
    const key = std.process.getEnvVarOwned(allocator, "BAG_ATTEST_KEY") catch {
        std.debug.print("FATAL: BAG_ATTEST_KEY is unset — refusing to attest (no dev-key fallback).\n", .{});
        std.process.exit(ex_config);
    };
    if (key.len < min_attest_key_len) {
        std.debug.print("FATAL: BAG_ATTEST_KEY is too short ({d} < {d} bytes).\n", .{ key.len, min_attest_key_len });
        std.process.exit(ex_config);
    }
    return key;
}

/// The id of the active HMAC key (BAG_ATTEST_KEY_ID), default "default". Written
/// into the envelope so thaw can select the matching verifying key during rotation.
fn activeKeyId(allocator: std.mem.Allocator) ![]const u8 {
    return std.process.getEnvVarOwned(allocator, "BAG_ATTEST_KEY_ID") catch
        try allocator.dupe(u8, "default");
}

/// The attestation mode (BAG_MODE), default "prod". Bound into the verdict so a
/// dev/laptop verdict carries `mode=dev` and the bridge can refuse to green it.
fn currentMode(allocator: std.mem.Allocator) ![]const u8 {
    return std.process.getEnvVarOwned(allocator, "BAG_MODE") catch
        try allocator.dupe(u8, "prod");
}

/// A key_id can name a keyring file, so it must not be able to escape the keyring
/// directory. Allow only `[A-Za-z0-9._-]`, non-empty, <= 128 chars, no `..`.
/// Fail-closed: an invalid id resolves to no key, i.e. a rejected verdict.
fn validKeyId(s: []const u8) bool {
    if (s.len == 0 or s.len > 128) return false;
    for (s) |c| {
        const ok = (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or c == '.' or c == '_' or c == '-';
        if (!ok) return false;
    }
    return std.mem.indexOf(u8, s, "..") == null;
}

/// Resolve the verifying HMAC key for a given `key_id` when THAWING. Looks first
/// in the keyring (`~/.config/bag/attest-keys/<key_id>`), then falls back to
/// BAG_ATTEST_KEY when its id (BAG_ATTEST_KEY_ID, default "default") matches.
/// Returns `null` (→ caller rejects as tampered) when the id is invalid or no key
/// is found — never a soft pass, and never reading a file outside the keyring dir.
fn attestKeyForId(allocator: std.mem.Allocator, key_id: []const u8) !?[]const u8 {
    if (!validKeyId(key_id)) return null;

    // 1. Keyring file (supports overlap-window rotation: old keys live on disk).
    if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
        defer allocator.free(home);
        const path = try std.fmt.allocPrint(allocator, "{s}/.config/bag/attest-keys/{s}", .{ home, key_id });
        defer allocator.free(path);
        if (std.fs.cwd().openFile(path, .{})) |file| {
            defer file.close();
            const raw = try file.readToEndAlloc(allocator, 4096);
            defer allocator.free(raw);
            const trimmed = std.mem.trim(u8, raw, " \r\n\t");
            if (trimmed.len >= min_attest_key_len) return try allocator.dupe(u8, trimmed);
        } else |_| {}
    } else |_| {}

    // 2. Env fallback, only when the active key's id matches the requested one.
    const active_id = std.process.getEnvVarOwned(allocator, "BAG_ATTEST_KEY_ID") catch
        try allocator.dupe(u8, "default");
    defer allocator.free(active_id);
    if (std.mem.eql(u8, active_id, key_id)) {
        if (std.process.getEnvVarOwned(allocator, "BAG_ATTEST_KEY")) |key| {
            if (key.len >= min_attest_key_len) return key;
            allocator.free(key);
        } else |_| {}
    }
    return null;
}

/// Resolve the ed25519 signing key path: BAG_SIGN_KEY_PATH, else
/// ~/.ssh/id_ed25519_signing. Returns null only when HOME is also unavailable.
fn resolveSignKeyPath(allocator: std.mem.Allocator) ?[]u8 {
    if (std.process.getEnvVarOwned(allocator, "BAG_SIGN_KEY_PATH")) |p| return p else |_| {}
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return null;
    defer allocator.free(home);
    return std.fmt.allocPrint(allocator, "{s}/.ssh/id_ed25519_signing", .{home}) catch null;
}

/// Sign `baton` in place, or abort the process. Mandatory-ed25519 means a verdict
/// that cannot be signed must never be frozen — there is no HMAC-only fallback.
fn signOrExit(allocator: std.mem.Allocator, baton: *CheckBaton, sign_key_path: []const u8) void {
    if (baton.signEd25519(allocator, sign_key_path)) |r| {
        baton.signature = r.sig;
        baton.signing_pubkey = r.pubkey;
    } else |err| {
        std.debug.print("FATAL: ed25519 signing failed ({s}) using key {s} — refusing to freeze an unsigned verdict.\n", .{ @errorName(err), sign_key_path });
        std.process.exit(ex_config);
    }
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
        // Print "name<TAB>cost" per node from the single mirrored manifest, so
        // the Elixir planner reads both the node list and its tropical grade
        // from here instead of keeping its own copy.
        for (estate.estate) |node| {
            try printOut(allocator, "{s}\t{d}\n", .{ node.name, node.cost });
        }
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

        // Exit code is the signal (0 = match, 1 = no match); the Elixir
        // Executor reads the status, not any stdout/stderr text.
        if (!has_unknown and estate.nodeSatisfies(node_name, reqs[0..valid_count])) {
            std.process.exit(0);
        } else {
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

        // Fail-closed attestation context: a real shared key (>= 32 bytes), a key
        // id, a mode, and a usable ed25519 signing key are ALL required before any
        // verdict (even a pending/suspended one) can be frozen.
        const key = try activeAttestKey(allocator);
        defer allocator.free(key);
        const key_id = try activeKeyId(allocator);
        defer allocator.free(key_id);
        const mode = try currentMode(allocator);
        defer allocator.free(mode);
        const sign_key_path = resolveSignKeyPath(allocator) orelse {
            std.debug.print("FATAL: no ed25519 signing key (set BAG_SIGN_KEY_PATH or provide ~/.ssh/id_ed25519_signing).\n", .{});
            std.process.exit(ex_config);
        };
        defer allocator.free(sign_key_path);

        // 1. Capability gate: only run on a node that satisfies the requirement.
        if (!estate.nodeSatisfies(node, &[_]estate.Capability{cap})) {
            try printOut(allocator, "VERDICT=suspended\nReason: node '{s}' lacks capability '{s}'. Work suspended (no minutes burned).\n", .{ node, @tagName(cap) });
            // Freeze a pending Baton so the work can migrate to a capable node.
            const joined = try std.mem.join(allocator, " ", cmd_argv);
            defer allocator.free(joined);
            var baton = CheckBaton{ .id = check_id, .check_id = check_id, .node = node, .required_cap = cap, .verdict = .pending, .exit_code = -1, .command = joined, .mode = mode, .key_id = key_id };
            signOrExit(allocator, &baton, sign_key_path);
            try baton.freeze(allocator, freeze_path, key);
            std.process.exit(2);
        }

        // 2. Detect WASI mode: wasm://<path> prefix switches to wasmtime execution.
        //    The module is hashed so the exact Wasm binary is bound to the verdict.
        const wasm_module_path: ?[]const u8 = if (cmd_argv.len > 0 and
            std.mem.startsWith(u8, cmd_argv[0], "wasm://"))
            cmd_argv[0]["wasm://".len..]
        else
            null;
        const wasm_digest_opt: ?[64]u8 = if (wasm_module_path) |wmp|
            crypto.hashFileSha256(wmp) catch null
        else
            null;

        // Build exec argv: wasmtime run --dir=. <module> [rest...] or the original argv.
        var wasm_argv_buf: [32][]const u8 = undefined;
        const exec_argv: []const []const u8 = if (wasm_module_path) |wmp| blk: {
            wasm_argv_buf[0] = "wasmtime";
            wasm_argv_buf[1] = "run";
            wasm_argv_buf[2] = "--dir=.";
            wasm_argv_buf[3] = wmp;
            const extra = cmd_argv.len - 1;
            if (extra > 0) @memcpy(wasm_argv_buf[4 .. 4 + extra], cmd_argv[1..]);
            break :blk wasm_argv_buf[0 .. 4 + extra];
        } else cmd_argv;

        // 3. Execute the real check on this (capable) node.
        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = exec_argv,
        });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        const code: i32 = switch (result.term) {
            .Exited => |c| @intCast(c),
            else => 1,
        };
        const verdict: Verdict = if (code == 0) .pass else .fail;

        // 4. Hash the artifact report if BAG_ARTIFACT_PATH is set (generic: works
        //    for any check that writes a file — Scorecard JSON, SARIF, SBOM, etc.).
        const artifact_path_env = std.process.getEnvVarOwned(allocator, "BAG_ARTIFACT_PATH") catch null;
        defer if (artifact_path_env) |p| allocator.free(p);
        const artifact_sha256_opt: ?[64]u8 = if (artifact_path_env) |ap|
            crypto.hashFileSha256(ap) catch null
        else
            null;

        // 5. Read optional v2 metadata: tool version + inline artifact (≤ BAG_ARTIFACT_INLINE_MAX bytes).
        const tool_version_opt = std.process.getEnvVarOwned(allocator, "BAG_TOOL_VERSION") catch null;
        defer if (tool_version_opt) |tv| allocator.free(tv);

        const inline_max: usize = blk: {
            const v = std.process.getEnvVarOwned(allocator, "BAG_ARTIFACT_INLINE_MAX") catch null;
            defer if (v) |s| allocator.free(s);
            break :blk if (v) |s| std.fmt.parseInt(usize, s, 10) catch 4096 else 4096;
        };
        const artifact_inline_b64_opt: ?[]u8 = if (artifact_path_env) |ap| blk: {
            const raw = std.fs.cwd().readFileAlloc(allocator, ap, inline_max) catch break :blk null;
            defer allocator.free(raw);
            const b64_len = std.base64.standard.Encoder.calcSize(raw.len);
            const b64_buf = try allocator.alloc(u8, b64_len);
            _ = std.base64.standard.Encoder.encode(b64_buf, raw);
            break :blk b64_buf;
        } else null;
        defer if (artifact_inline_b64_opt) |b| allocator.free(b);

        // 6. Build the Baton with the executed verdict and all metadata.
        const joined = try std.mem.join(allocator, " ", cmd_argv);
        defer allocator.free(joined);
        var baton = CheckBaton{
            .id = check_id,
            .check_id = check_id,
            .node = node,
            .required_cap = cap,
            .verdict = verdict,
            .exit_code = code,
            .command = joined,
            .mode = mode,
            .key_id = key_id,
            .artifact_path = artifact_path_env,
            .artifact_sha256 = artifact_sha256_opt,
            .wasm_path = wasm_module_path,
            .wasm_digest = wasm_digest_opt,
            .tool_version = tool_version_opt,
            .artifact_inline_b64 = artifact_inline_b64_opt,
        };

        // 7. Mandatory ed25519 signing for authenticity-evident attestation.
        //    Fail-CLOSED: if the signing key is absent or unreadable the verdict is
        //    NOT frozen (process aborts). Uses BAG_SIGN_KEY_PATH or the estate
        //    signing key ~/.ssh/id_ed25519_signing (id_ed25519 is auth-only).
        signOrExit(allocator, &baton, sign_key_path);

        // 8. Freeze (HMAC + mandatory ed25519 signature).
        try baton.freeze(allocator, freeze_path, key);

        const has_artifact = if (artifact_sha256_opt != null) "yes" else "no";
        const has_sig = if (baton.signature != null) "yes" else "no";
        const has_wasm = if (wasm_module_path != null) "yes" else "no";
        try printOut(allocator, "VERDICT={s}\ncheck_id={s} node={s} cap={s} exit_code={d} artifact={s} wasm={s} ed25519={s}\nFrozen+attested to {s} (0 GitHub minutes)\n", .{ @tagName(verdict), check_id, node, @tagName(cap), code, has_artifact, has_wasm, has_sig, freeze_path });
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

        // Select the verifying key by the envelope's key_id (keyring + rotation).
        // A missing/invalid key_id resolves to no key ⇒ rejected, never a soft pass.
        const key = (try attestKeyForId(allocator, baton.key_id)) orelse {
            try printOut(allocator, "VERDICT=tampered\ncheck_id={s}: no attestation key for key_id '{s}' — verdict REJECTED.\n", .{ baton.check_id, baton.key_id });
            std.process.exit(3);
        };
        defer allocator.free(key);

        // Fail-closed: must be v2, HMAC-valid, signed, and the signature must verify.
        const attest = try baton.checkAttestation(allocator, key);
        if (attest != .ok) {
            const reason: []const u8 = switch (attest) {
                .bad_version => "version (not v2)",
                .bad_hmac => "hmac",
                .missing_sig => "unsigned",
                .bad_sig => "ed25519",
                .ok => unreachable,
            };
            try printOut(allocator, "VERDICT=tampered\ncheck_id={s}: attestation failed ({s}) — verdict REJECTED.\n", .{ baton.check_id, reason });
            std.process.exit(3);
        }

        try printOut(allocator, "VERDICT={s}\ncheck_id={s} node={s} cap={s} exit_code={d}\ncommand={s}\nmode={s}\nattestation=hmac:verified ed25519:verified\n", .{ @tagName(baton.verdict), baton.check_id, baton.node, @tagName(baton.required_cap), baton.exit_code, baton.command, baton.mode });
        if (baton.tool_version) |tv| try printOut(allocator, "tool_version={s}\n", .{tv});
        if (baton.wasm_path) |wp| try printOut(allocator, "wasm_path={s}\n", .{wp});
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

// ── Tests ──────────────────────────────────────────────────────────────────────

// Pull the extracted modules' tests into this test binary. `crypto` is already
// referenced throughout, but `store` is not yet wired into any code path, so this
// keeps `zig build test` running its `atomicWrite` test until a later phase uses it.
test {
    std.testing.refAllDecls(crypto);
    std.testing.refAllDecls(store);
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

test "Capability.fromString recognises scorecard (tag 11)" {
    const cap = estate.Capability.fromString("scorecard");
    try std.testing.expect(cap != null);
    try std.testing.expect(cap.? == .scorecard);
    try std.testing.expect(@intFromEnum(cap.?) == 11);
}

test "Capability.fromString rejects unknown capabilities (fail closed)" {
    try std.testing.expect(estate.Capability.fromString("bogus-unknown-cap") == null);
    try std.testing.expect(estate.Capability.fromString("") == null);
    try std.testing.expect(estate.Capability.fromString("SCORECARD") == null); // case-sensitive
}

test "CheckBaton with artifact_sha256 round-trips and verifies attestation" {
    const a = std.testing.allocator;
    const key = "test-key";
    var sha: [64]u8 = undefined;
    @memset(&sha, 'a'); // deterministic dummy hex value for test
    const original = CheckBaton{
        .id = "cib-art-001",
        .check_id = "ossf-scorecard",
        .node = "mesh-server-1",
        .required_cap = .scorecard,
        .verdict = .pass,
        .exit_code = 0,
        .command = "./scripts/baton-scorecard.sh",
        .artifact_path = "_bag_artifacts/scorecard/scorecard.json",
        .artifact_sha256 = sha,
    };
    const path = "test-ci-baton-artifact-rt.txt";
    try original.freeze(a, path, key);
    defer std.fs.cwd().deleteFile(path) catch {};

    var thawed = try CheckBaton.thaw(a, path);
    defer thawed.deinit(a);

    try std.testing.expect(thawed.artifact_sha256 != null);
    try std.testing.expectEqualSlices(u8, sha[0..], thawed.artifact_sha256.?[0..]);
    try std.testing.expectEqualStrings("_bag_artifacts/scorecard/scorecard.json", thawed.artifact_path.?);
    try std.testing.expect(try thawed.verify(a, key));
}

test "tampering with artifact_sha256 is detected on thaw" {
    const a = std.testing.allocator;
    const key = "test-key";
    var sha: [64]u8 = undefined;
    @memset(&sha, 'b');
    const original = CheckBaton{
        .id = "cib-art-002",
        .check_id = "ossf-scorecard",
        .node = "mesh-server-1",
        .required_cap = .scorecard,
        .verdict = .pass,
        .exit_code = 0,
        .command = "./scripts/baton-scorecard.sh",
        .artifact_sha256 = sha,
    };
    const path = "test-ci-baton-artifact-tamper.txt";
    try original.freeze(a, path, key);
    defer std.fs.cwd().deleteFile(path) catch {};

    // Replace the artifact_sha256 line in the frozen envelope.
    const content = blk: {
        const rf = try std.fs.cwd().openFile(path, .{});
        defer rf.close();
        break :blk try rf.readToEndAlloc(a, 8192);
    };
    defer a.free(content);
    const prefix = "artifact_sha256=";
    var old_line: [prefix.len + 64]u8 = undefined;
    @memcpy(old_line[0..prefix.len], prefix);
    @memset(old_line[prefix.len..], 'b');
    var new_line: [prefix.len + 64]u8 = undefined;
    @memcpy(new_line[0..prefix.len], prefix);
    @memset(new_line[prefix.len..], 'c');
    const forged = try std.mem.replaceOwned(u8, a, content, &old_line, &new_line);
    defer a.free(forged);
    {
        const f = try std.fs.cwd().createFile(path, .{});
        defer f.close();
        try f.writeAll(forged);
    }

    var thawed = try CheckBaton.thaw(a, path);
    defer thawed.deinit(a);
    try std.testing.expect(!try thawed.verify(a, key)); // tampered artifact sha → rejected
}

test "v2 envelope with no artifact fields still verifies (optional fields absent)" {
    const a = std.testing.allocator;
    const key = "test-key";
    // No artifact_sha256 — the optional extension is simply omitted.
    const original = CheckBaton{
        .id = "cib-compat-001",
        .check_id = "zig-fmt",
        .node = "mesh-server-1",
        .required_cap = .zig,
        .verdict = .pass,
        .exit_code = 0,
        .command = "zig fmt --check build.zig",
    };
    const path = "test-ci-baton-compat.txt";
    try original.freeze(a, path, key);
    defer std.fs.cwd().deleteFile(path) catch {};

    var thawed = try CheckBaton.thaw(a, path);
    defer thawed.deinit(a);

    try std.testing.expect(thawed.artifact_sha256 == null);
    try std.testing.expect(thawed.artifact_path == null);
    try std.testing.expect(try thawed.verify(a, key));
}

test "ed25519 sign/verify round-trip using synthetic key" {
    const a = std.testing.allocator;
    const seed = [_]u8{0x42} ** 32; // deterministic test seed
    var baton = CheckBaton{
        .id = "cib-ed25519-001",
        .check_id = "zig-fmt",
        .node = "mesh-server-1",
        .required_cap = .zig,
        .verdict = .pass,
        .exit_code = 0,
        .command = "zig fmt --check build.zig",
    };
    const ed_result = try baton.signEd25519WithSeed(a, seed);
    baton.signature = ed_result.sig;
    baton.signing_pubkey = ed_result.pubkey;
    try std.testing.expect(try baton.verifyEd25519(a));
}

test "ed25519 tampered verdict is rejected" {
    const a = std.testing.allocator;
    const seed = [_]u8{0x42} ** 32;
    const original = CheckBaton{
        .id = "cib-ed25519-002",
        .check_id = "zig-fmt",
        .node = "mesh-server-1",
        .required_cap = .zig,
        .verdict = .pass,
        .exit_code = 0,
        .command = "zig fmt --check build.zig",
    };
    const ed_result = try original.signEd25519WithSeed(a, seed);
    // Signature was computed over .pass verdict; .fail should not verify.
    var tampered = original;
    tampered.verdict = .fail;
    tampered.signature = ed_result.sig;
    tampered.signing_pubkey = ed_result.pubkey;
    try std.testing.expect(!try tampered.verifyEd25519(a));
}

test "ed25519 signature survives freeze/thaw cycle" {
    const a = std.testing.allocator;
    const seed = [_]u8{0x43} ** 32;
    var original = CheckBaton{
        .id = "cib-ed25519-003",
        .check_id = "zig-fmt",
        .node = "mesh-server-1",
        .required_cap = .zig,
        .verdict = .pass,
        .exit_code = 0,
        .command = "zig fmt --check build.zig",
    };
    const ed_result = try original.signEd25519WithSeed(a, seed);
    original.signature = ed_result.sig;
    original.signing_pubkey = ed_result.pubkey;

    const path = "test-ci-baton-ed25519-rt.txt";
    try original.freeze(a, path, "test-key");
    defer std.fs.cwd().deleteFile(path) catch {};

    var thawed = try CheckBaton.thaw(a, path);
    defer thawed.deinit(a);

    try std.testing.expect(thawed.signature != null);
    try std.testing.expect(thawed.signing_pubkey != null);
    try std.testing.expect(try thawed.verifyEd25519(a));
    try std.testing.expect(try thawed.verify(a, "test-key")); // HMAC still works too
}

test "baton without ed25519 signature returns false from verifyEd25519 (not an error)" {
    const a = std.testing.allocator;
    const baton = CheckBaton{
        .id = "cib-ed25519-004",
        .check_id = "zig-fmt",
        .node = "mesh-server-1",
        .required_cap = .zig,
        .verdict = .pass,
        .exit_code = 0,
        .command = "zig fmt --check build.zig",
    };
    // No signature present → false, not an error.
    try std.testing.expect(!try baton.verifyEd25519(a));
}

test "Capability.fromString recognises wasm (tag 12)" {
    const cap = estate.Capability.fromString("wasm");
    try std.testing.expect(cap != null);
    try std.testing.expect(cap.? == .wasm);
    try std.testing.expect(@intFromEnum(cap.?) == 12);
}

test "wasm_digest extends canonical string and changes HMAC" {
    const a = std.testing.allocator;
    const key = "test-key";
    var sha: [64]u8 = undefined;
    @memset(&sha, 'w');
    const with_wasm = CheckBaton{
        .id = "cib-wasm-001",
        .check_id = "zig-fmt-wasm",
        .node = "mesh-server-1",
        .required_cap = .wasm,
        .verdict = .pass,
        .exit_code = 0,
        .command = "wasm://zig-out/lib/zig_fmt.wasm src/main.zig",
        .wasm_digest = sha,
    };
    const without_wasm = CheckBaton{
        .id = "cib-wasm-001",
        .check_id = "zig-fmt-wasm",
        .node = "mesh-server-1",
        .required_cap = .wasm,
        .verdict = .pass,
        .exit_code = 0,
        .command = "wasm://zig-out/lib/zig_fmt.wasm src/main.zig",
    };
    const h1 = try with_wasm.digestHex(a, key);
    const h2 = try without_wasm.digestHex(a, key);
    try std.testing.expect(!std.mem.eql(u8, h1[0..], h2[0..]));
}

test "tool_version extends canonical string and changes HMAC" {
    const a = std.testing.allocator;
    const key = "test-key";
    const with_ver = CheckBaton{
        .id = "cib-tv-001",
        .check_id = "scorecard",
        .node = "mesh-server-1",
        .required_cap = .scorecard,
        .verdict = .pass,
        .exit_code = 0,
        .command = "./scripts/baton-scorecard.sh",
        .tool_version = "scorecard 5.1.0",
    };
    const without_ver = CheckBaton{
        .id = "cib-tv-001",
        .check_id = "scorecard",
        .node = "mesh-server-1",
        .required_cap = .scorecard,
        .verdict = .pass,
        .exit_code = 0,
        .command = "./scripts/baton-scorecard.sh",
    };
    const h1 = try with_ver.digestHex(a, key);
    const h2 = try without_ver.digestHex(a, key);
    try std.testing.expect(!std.mem.eql(u8, h1[0..], h2[0..]));
}

test "wasm_digest + tool_version round-trip freeze/thaw with attestation" {
    const a = std.testing.allocator;
    const key = "test-key";
    var wd: [64]u8 = undefined;
    @memset(&wd, 'f');
    const original = CheckBaton{
        .id = "cib-v2-001",
        .check_id = "zig-fmt-wasm",
        .node = "mesh-server-1",
        .required_cap = .wasm,
        .verdict = .pass,
        .exit_code = 0,
        .command = "wasm://zig-out/lib/zig_fmt.wasm src/main.zig",
        .wasm_digest = wd,
        .tool_version = "zig 0.15.2",
    };
    const path = "test-ci-baton-v2-rt.txt";
    try original.freeze(a, path, key);
    defer std.fs.cwd().deleteFile(path) catch {};

    var thawed = try CheckBaton.thaw(a, path);
    defer thawed.deinit(a);

    try std.testing.expect(thawed.wasm_digest != null);
    try std.testing.expectEqualSlices(u8, wd[0..], thawed.wasm_digest.?[0..]);
    try std.testing.expect(thawed.tool_version != null);
    try std.testing.expectEqualStrings("zig 0.15.2", thawed.tool_version.?);
    try std.testing.expect(try thawed.verify(a, key));
}

test "artifact_inline_b64 round-trips freeze/thaw" {
    const a = std.testing.allocator;
    const key = "test-key";
    const original = CheckBaton{
        .id = "cib-b64-001",
        .check_id = "scorecard",
        .node = "mesh-server-1",
        .required_cap = .scorecard,
        .verdict = .pass,
        .exit_code = 0,
        .command = "./scripts/baton-scorecard.sh",
        .artifact_inline_b64 = "eyJzY29yZSI6OX0=",
    };
    const path = "test-ci-baton-b64-rt.txt";
    try original.freeze(a, path, key);
    defer std.fs.cwd().deleteFile(path) catch {};

    var thawed = try CheckBaton.thaw(a, path);
    defer thawed.deinit(a);

    try std.testing.expect(thawed.artifact_inline_b64 != null);
    try std.testing.expectEqualStrings("eyJzY29yZSI6OX0=", thawed.artifact_inline_b64.?);
    try std.testing.expect(try thawed.verify(a, key));
}

test "v2 envelope with no extension fields still verifies (optional fields absent)" {
    const a = std.testing.allocator;
    const key = "test-key";
    const original = CheckBaton{
        .id = "cib-v2-compat-001",
        .check_id = "zig-fmt",
        .node = "mesh-server-1",
        .required_cap = .zig,
        .verdict = .pass,
        .exit_code = 0,
        .command = "zig fmt --check build.zig",
    };
    const path = "test-ci-baton-v2-compat.txt";
    try original.freeze(a, path, key);
    defer std.fs.cwd().deleteFile(path) catch {};

    var thawed = try CheckBaton.thaw(a, path);
    defer thawed.deinit(a);

    try std.testing.expect(thawed.wasm_digest == null);
    try std.testing.expect(thawed.tool_version == null);
    try std.testing.expect(thawed.artifact_inline_b64 == null);
    try std.testing.expect(try thawed.verify(a, key));
}

// ── Phase 1 security: v2 binding + mandatory ed25519 + key_id ─────────────────

test "mode is bound into the canonical string (dev and prod verdicts differ)" {
    const a = std.testing.allocator;
    const key = "test-key";
    const prod_b = CheckBaton{
        .id = "cib-mode-001",
        .check_id = "zig-fmt",
        .node = "mesh-server-1",
        .required_cap = .zig,
        .verdict = .pass,
        .exit_code = 0,
        .command = "zig fmt --check build.zig",
        .mode = "prod",
    };
    const dev_b = CheckBaton{
        .id = "cib-mode-001",
        .check_id = "zig-fmt",
        .node = "mesh-server-1",
        .required_cap = .zig,
        .verdict = .pass,
        .exit_code = 0,
        .command = "zig fmt --check build.zig",
        .mode = "dev",
    };
    const h1 = try prod_b.digestHex(a, key);
    const h2 = try dev_b.digestHex(a, key);
    // A dev verdict can never present the same HMAC as the prod one (quarantine).
    try std.testing.expect(!std.mem.eql(u8, h1[0..], h2[0..]));
}

test "key_id is bound into the canonical string" {
    const a = std.testing.allocator;
    const key = "test-key";
    const k1 = CheckBaton{
        .id = "cib-kid-001",
        .check_id = "zig-fmt",
        .node = "mesh-server-1",
        .required_cap = .zig,
        .verdict = .pass,
        .exit_code = 0,
        .command = "zig fmt --check build.zig",
        .key_id = "default",
    };
    const k2 = CheckBaton{
        .id = "cib-kid-001",
        .check_id = "zig-fmt",
        .node = "mesh-server-1",
        .required_cap = .zig,
        .verdict = .pass,
        .exit_code = 0,
        .command = "zig fmt --check build.zig",
        .key_id = "2026-06-rotation",
    };
    const h1 = try k1.digestHex(a, key);
    const h2 = try k2.digestHex(a, key);
    try std.testing.expect(!std.mem.eql(u8, h1[0..], h2[0..]));
}

test "checkAttestation accepts a signed v2 envelope" {
    const a = std.testing.allocator;
    const key = "test-key";
    const seed = [_]u8{0x51} ** 32;
    var original = CheckBaton{
        .id = "cib-att-ok",
        .check_id = "zig-fmt",
        .node = "mesh-server-1",
        .required_cap = .zig,
        .verdict = .pass,
        .exit_code = 0,
        .command = "zig fmt --check build.zig",
    };
    const ed = try original.signEd25519WithSeed(a, seed);
    original.signature = ed.sig;
    original.signing_pubkey = ed.pubkey;
    const path = "test-att-ok.txt";
    try original.freeze(a, path, key);
    defer std.fs.cwd().deleteFile(path) catch {};

    var thawed = try CheckBaton.thaw(a, path);
    defer thawed.deinit(a);
    try std.testing.expect(thawed.version == 2);
    try std.testing.expect((try thawed.checkAttestation(a, key)) == .ok);
}

test "checkAttestation rejects an unsigned (HMAC-only) v2 envelope" {
    const a = std.testing.allocator;
    const key = "test-key";
    // Freeze WITHOUT signing — a perfectly valid HMAC but no ed25519 signature.
    const original = CheckBaton{
        .id = "cib-att-unsigned",
        .check_id = "zig-fmt",
        .node = "mesh-server-1",
        .required_cap = .zig,
        .verdict = .pass,
        .exit_code = 0,
        .command = "zig fmt --check build.zig",
    };
    const path = "test-att-unsigned.txt";
    try original.freeze(a, path, key);
    defer std.fs.cwd().deleteFile(path) catch {};

    var thawed = try CheckBaton.thaw(a, path);
    defer thawed.deinit(a);
    try std.testing.expect(try thawed.verify(a, key)); // HMAC alone is fine...
    try std.testing.expect((try thawed.checkAttestation(a, key)) == .missing_sig); // ...but rejected.
}

test "checkAttestation rejects a non-v2 (v1) envelope" {
    const a = std.testing.allocator;
    const key = "test-key";
    var b = CheckBaton{
        .id = "cib-att-v1",
        .check_id = "zig-fmt",
        .node = "mesh-server-1",
        .required_cap = .zig,
        .verdict = .pass,
        .exit_code = 0,
        .command = "zig fmt --check build.zig",
    };
    b.version = 1; // simulate a thawed legacy envelope
    try std.testing.expect((try b.checkAttestation(a, key)) == .bad_version);
}

test "checkAttestation rejects a tampered verdict (bad hmac)" {
    const a = std.testing.allocator;
    const key = "test-key";
    const seed = [_]u8{0x52} ** 32;
    var original = CheckBaton{
        .id = "cib-att-tamper",
        .check_id = "zig-fmt",
        .node = "mesh-server-1",
        .required_cap = .zig,
        .verdict = .fail,
        .exit_code = 1,
        .command = "zig fmt --check src/main.zig",
    };
    const ed = try original.signEd25519WithSeed(a, seed);
    original.signature = ed.sig;
    original.signing_pubkey = ed.pubkey;
    const path = "test-att-tamper.txt";
    try original.freeze(a, path, key);
    defer std.fs.cwd().deleteFile(path) catch {};

    // Forge verdict=fail → pass in the frozen envelope.
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
    try std.testing.expect((try thawed.checkAttestation(a, key)) == .bad_hmac);
}

test "validKeyId accepts plain ids and rejects path traversal" {
    try std.testing.expect(validKeyId("default"));
    try std.testing.expect(validKeyId("2026-06-rotation_1"));
    try std.testing.expect(!validKeyId(""));
    try std.testing.expect(!validKeyId("a/b"));
    try std.testing.expect(!validKeyId("../../etc/passwd"));
    try std.testing.expect(!validKeyId(".."));
}
