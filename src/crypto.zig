// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//! Leaf cryptographic + key-parsing helpers factored out of main.zig.
//! These are behaviour-preserving moves: the BAG-CHECK-BATON envelope bytes,
//! HMAC, and ed25519 results are byte-for-byte identical to the inline versions.
const std = @import("std");

/// Lowercase-hex-encode a fixed-size byte array. Factors the encode loop that
/// was duplicated for HMAC digests, ed25519 signatures, and SHA-256 file hashes.
pub fn bytesToHex(comptime N: usize, bytes: [N]u8) [N * 2]u8 {
    const hexchars = "0123456789abcdef";
    var hex: [N * 2]u8 = undefined;
    for (bytes, 0..) |byte, i| {
        hex[i * 2] = hexchars[byte >> 4];
        hex[i * 2 + 1] = hexchars[byte & 0x0f];
    }
    return hex;
}

/// Hex-decode `hex` into `dst`; `dst.len * 2 == hex.len` must hold.
pub fn hexDecode(dst: []u8, hex: []const u8) !void {
    if (hex.len != dst.len * 2) return error.InvalidHexLength;
    for (0..dst.len) |i| {
        const hi = std.fmt.charToDigit(hex[i * 2], 16) catch return error.InvalidHex;
        const lo = std.fmt.charToDigit(hex[i * 2 + 1], 16) catch return error.InvalidHex;
        dst[i] = @as(u8, @intCast(hi)) << 4 | @as(u8, @intCast(lo));
    }
}

/// Parse an unencrypted OpenSSH ed25519 private key file and return the 32-byte seed.
/// Encrypted keys (cipher != "none") are rejected with EncryptedKeyNotSupported.
pub fn readEd25519Seed(allocator: std.mem.Allocator, path: []const u8) ![32]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const pem = try file.readToEndAlloc(allocator, 8192);
    defer allocator.free(pem);

    // Strip PEM header/footer and concatenate base64 payload lines.
    var b64: std.ArrayList(u8) = .empty;
    defer b64.deinit(allocator);
    var iter = std.mem.splitScalar(u8, pem, '\n');
    while (iter.next()) |line| {
        const t = std.mem.trim(u8, line, " \r\t");
        if (t.len == 0 or std.mem.startsWith(u8, t, "-----")) continue;
        try b64.appendSlice(allocator, t);
    }

    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(b64.items) catch return error.InvalidKeyFormat;
    const decoded = try allocator.alloc(u8, decoded_len);
    defer allocator.free(decoded);
    try std.base64.standard.Decoder.decode(decoded, b64.items);

    // Validate OpenSSH magic.
    const magic = "openssh-key-v1\x00";
    if (decoded.len < magic.len or !std.mem.startsWith(u8, decoded, magic)) return error.NotOpenSSHKey;
    var pos: usize = magic.len;

    // cipher name — must be "none" (unencrypted).
    if (pos + 4 > decoded.len) return error.InvalidKeyFormat;
    const cipher_len = std.mem.readInt(u32, decoded[pos..][0..4], .big);
    pos += 4;
    if (pos + cipher_len > decoded.len) return error.InvalidKeyFormat;
    if (!std.mem.eql(u8, decoded[pos .. pos + cipher_len], "none")) return error.EncryptedKeyNotSupported;
    pos += cipher_len;

    // kdf name (skip).
    if (pos + 4 > decoded.len) return error.InvalidKeyFormat;
    const kdf_len = std.mem.readInt(u32, decoded[pos..][0..4], .big);
    pos += 4;
    if (pos + kdf_len > decoded.len) return error.InvalidKeyFormat;
    pos += kdf_len;

    // kdf options (skip).
    if (pos + 4 > decoded.len) return error.InvalidKeyFormat;
    const kdf_opts_len = std.mem.readInt(u32, decoded[pos..][0..4], .big);
    pos += 4;
    if (pos + kdf_opts_len > decoded.len) return error.InvalidKeyFormat;
    pos += kdf_opts_len;

    // nkeys (skip).
    if (pos + 4 > decoded.len) return error.InvalidKeyFormat;
    pos += 4;

    // public key blob (skip).
    if (pos + 4 > decoded.len) return error.InvalidKeyFormat;
    const pub_blob_len = std.mem.readInt(u32, decoded[pos..][0..4], .big);
    pos += 4;
    if (pos + pub_blob_len > decoded.len) return error.InvalidKeyFormat;
    pos += pub_blob_len;

    // private key blob length (skip — we parse the blob inline below).
    if (pos + 4 > decoded.len) return error.InvalidKeyFormat;
    pos += 4;

    // check1 == check2 (corruption guard).
    if (pos + 8 > decoded.len) return error.InvalidKeyFormat;
    if (!std.mem.eql(u8, decoded[pos .. pos + 4], decoded[pos + 4 .. pos + 8])) return error.KeyCorrupted;
    pos += 8;

    // key type.
    if (pos + 4 > decoded.len) return error.InvalidKeyFormat;
    const kt_len = std.mem.readInt(u32, decoded[pos..][0..4], .big);
    pos += 4;
    if (pos + kt_len > decoded.len) return error.InvalidKeyFormat;
    if (!std.mem.eql(u8, decoded[pos .. pos + kt_len], "ssh-ed25519")) return error.NotEd25519Key;
    pos += kt_len;

    // inner public key (skip).
    if (pos + 4 > decoded.len) return error.InvalidKeyFormat;
    const inner_pub_len = std.mem.readInt(u32, decoded[pos..][0..4], .big);
    pos += 4;
    if (pos + inner_pub_len > decoded.len) return error.InvalidKeyFormat;
    pos += inner_pub_len;

    // seed+pubkey field: 4-byte length (must be 64) + 32-byte seed + 32-byte pubkey.
    if (pos + 4 > decoded.len) return error.InvalidKeyFormat;
    const sp_len = std.mem.readInt(u32, decoded[pos..][0..4], .big);
    pos += 4;
    if (sp_len != 64 or pos + 32 > decoded.len) return error.InvalidKeyFormat;

    var seed: [32]u8 = undefined;
    @memcpy(&seed, decoded[pos..][0..32]);
    return seed;
}

/// Compute a hex-encoded SHA-256 digest of the file at `path` using streaming
/// reads so arbitrarily large report files (SARIF, SBOM, Scorecard JSON) do not
/// need to fit in memory. Returns 64 hex chars in a `[64]u8`.
pub fn hashFileSha256(path: []const u8) ![64]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const Sha256 = std.crypto.hash.sha2.Sha256;
    var hasher = Sha256.init(.{});
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = try file.read(&buf);
        if (n == 0) break;
        hasher.update(buf[0..n]);
    }
    var hash: [Sha256.digest_length]u8 = undefined;
    hasher.final(&hash);
    return bytesToHex(Sha256.digest_length, hash);
}

// ── Tests ──────────────────────────────────────────────────────────────────────

test "bytesToHex encodes lowercase hex" {
    const out = bytesToHex(4, [_]u8{ 0xde, 0xad, 0xbe, 0xef });
    try std.testing.expectEqualStrings("deadbeef", &out);
}

test "hexDecode round-trips known hex strings" {
    var buf: [4]u8 = undefined;
    try hexDecode(&buf, "deadbeef");
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xde, 0xad, 0xbe, 0xef }, &buf);
}

test "hexDecode rejects invalid hex chars" {
    var buf: [2]u8 = undefined;
    try std.testing.expectError(error.InvalidHex, hexDecode(&buf, "zz00"));
}

test "bytesToHex/hexDecode round-trip" {
    const bytes = [_]u8{ 0x00, 0x7f, 0x80, 0xff };
    const hex = bytesToHex(4, bytes);
    var back: [4]u8 = undefined;
    try hexDecode(&back, &hex);
    try std.testing.expectEqualSlices(u8, &bytes, &back);
}
