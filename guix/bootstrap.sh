#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# bootstrap.sh — stand up a bag-of-actions mesh node on Debian + Guix-as-pkgmgr.
#
# Idempotent: safe to re-run. Designed for mesh-server-1 (Debian 13, root). The
# long, RAM-hungry steps (`guix pull`, toolchain build) are isolated so the
# caller can background them; a swapfile is added first because `guix pull` can
# exceed 4 GB on a 2-vCPU box and OOM.
#
# Usage:
#   ./bootstrap.sh swap        # 1. add swap (guard guix pull OOM)
#   ./bootstrap.sh guix        # 2. install + authorize Guix (apt), start daemon
#   ./bootstrap.sh pull        # 3. guix pull to current channel  [LONG]
#   ./bootstrap.sh toolchain   # 4. install guix/manifest.scm     [LONG]
#   ./bootstrap.sh all         # run 1→4 in order
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SWAPFILE="${SWAPFILE:-/swapfile}"
SWAP_GB="${SWAP_GB:-4}"
log() { echo "[bootstrap $(date -u +%H:%M:%S)] $*"; }

# Resolve the freshest guix binary (the pulled one shadows the apt one).
guix_bin() {
  if [ -x /root/.config/guix/current/bin/guix ]; then
    echo /root/.config/guix/current/bin/guix
  else
    command -v guix
  fi
}

step_swap() {
  if swapon --show=NAME --noheadings 2>/dev/null | grep -q "$SWAPFILE"; then
    log "swap already active ($SWAPFILE)"; return
  fi
  log "creating ${SWAP_GB}G swapfile at $SWAPFILE"
  fallocate -l "${SWAP_GB}G" "$SWAPFILE" || dd if=/dev/zero of="$SWAPFILE" bs=1M count=$((SWAP_GB*1024))
  chmod 600 "$SWAPFILE"; mkswap "$SWAPFILE"; swapon "$SWAPFILE"
  grep -q "$SWAPFILE" /etc/fstab || echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
  log "swap on: $(free -h | awk '/Swap/{print $2}')"
}

step_guix() {
  # Debian 13 (trixie) DROPPED the `guix` apt package, so use the official
  # installer. It needs newgidmap (Debian `uidmap`) and authorizes the
  # bordeaux/ci substitute servers itself. Drive it non-interactively with
  # newlines (`yes ""`), per its own warning ("y" is rejected).
  if [ ! -x /root/.config/guix/current/bin/guix ] && ! command -v guix >/dev/null 2>&1; then
    log "installing guix via the official installer (apt package is gone on trixie)"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y uidmap wget xz-utils gnupg
    ( cd /tmp
      wget -q https://git.savannah.gnu.org/cgit/guix.git/plain/etc/guix-install.sh -O guix-install.sh
      chmod +x guix-install.sh
      yes "" | ./guix-install.sh )
  else
    log "guix already present"
  fi
  systemctl enable --now guix-daemon 2>/dev/null || true
  systemctl start guix-daemon 2>/dev/null || true
  log "guix: $("$(guix_bin)" --version | head -1)"
}

# idris2 + wasmtime are not in Guix; acquire them out-of-band. Stub for now —
# the pilot (first green check) does not need them; fill in before the Phase-3
# conformance gate (idris2) and the wasm:// path / Phase-5 frontier (wasmtime).
step_extra() {
  log "TODO: idris2 (Chez bootstrap build) + wasmtime (official static binary + C-API)"
  log "      not required for the first \$0 green check; see manifest.scm header."
}

step_pull() {
  log "guix pull — LONG (builds Guile modules; swap guards OOM)"
  guix pull
  log "pulled: $("$(guix_bin)" --version | head -1)"
}

step_toolchain() {
  local guix; guix="$(guix_bin)"
  log "installing toolchain from manifest.scm — LONG"
  "$guix" package -m "$HERE/manifest.scm"
  log "toolchain profile: /root/.guix-profile (source its etc/profile to use it)"
}

# `all` deliberately SKIPS `pull`: base Guix 1.5.0 already has the pilot toolchain
# at the versions we want (zig 0.15.2, elixir 1.19.3), and `guix pull` is the long,
# 4GB-OOM-prone step. Run `pull` explicitly only when a newer package is needed.
case "${1:-all}" in
  swap)      step_swap ;;
  guix)      step_guix ;;
  pull)      step_pull ;;
  toolchain) step_toolchain ;;
  extra)     step_extra ;;
  all)       step_swap; step_guix; step_toolchain; step_extra ;;
  *) echo "usage: $0 {swap|guix|pull|toolchain|extra|all}" >&2; exit 64 ;;
esac
