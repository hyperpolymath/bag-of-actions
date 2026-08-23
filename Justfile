# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Bag-of-Actions task runner — https://just.systems/man/en/
#
# A capability-aware continuation mesh: Zig execution host, Elixir/OTP control
# plane, Idris 2 verified ABI. This is the RSR Justfile with the project's real
# build/test/release/estate recipes filled in; the estate machinery imports
# (contractile, groove, assess, validate, proofs) and hooks are preserved.
#
# Run `just` to see all available recipes
# Run `just cookbook` to generate docs/just-cookbook.adoc
# Run `just combinations` to see matrix recipe options

set shell := ["bash", "-uc"]
set dotenv-load := true
set positional-arguments := true

# Import auto-generated contractile recipes (must-check, trust-verify, etc.)
# Re-generate with: contractile gen-just
import? "build/contractile.just"

# Project metadata
project := "bag-of-actions"
OWNER := "hyperpolymath"
REPO := "bag-of-actions"
version := "0.1.0"
tier := "infrastructure"  # 1 | 2 | infrastructure

# ═══════════════════════════════════════════════════════════════════════════════
# DEFAULT & HELP
# ═══════════════════════════════════════════════════════════════════════════════

# Show all available recipes with descriptions
default:
    @just --list --unsorted

# Show detailed help for a specific recipe
help recipe="":
    #!/usr/bin/env bash
    if [ -z "{{recipe}}" ]; then
        just --list --unsorted
        echo ""
        echo "Usage: just help <recipe>"
        echo "       just cookbook     # Generate full documentation"
        echo "       just combinations # Show matrix recipes"
    else
        just --show "{{recipe}}" 2>/dev/null || echo "Recipe '{{recipe}}' not found"
    fi

# Show this project's info
info:
    @echo "Project: {{project}}"
    @echo "Version: {{version}}"
    @echo "RSR Tier: {{tier}}"
    @echo "Recipes: $(just --summary | wc -w)"
    @[ -f ".machine_readable/STATE.a2ml" ] && grep -oP 'phase\s*=\s*"\K[^"]+' .machine_readable/STATE.a2ml | head -1 | xargs -I{} echo "Phase: {}" || true

# Run Invariant Path overlay tools for this repository
invariant-path *ARGS:
    ./scripts/invariant-path.sh {{ARGS}}

# ═══════════════════════════════════════════════════════════════════════════════
# INIT — see build/just/init.just
# ═══════════════════════════════════════════════════════════════════════════════

import? "build/just/init.just"

# ═══════════════════════════════════════════════════════════════════════════════
# GROOVE PROTOCOL — see build/just/groove.just
# ═══════════════════════════════════════════════════════════════════════════════

import? "build/just/groove.just"

# ═══════════════════════════════════════════════════════════════════════════════
# PROJECT SELF-ASSESSMENT + OPENSSF COMPLIANCE — see build/just/assess.just
# ═══════════════════════════════════════════════════════════════════════════════

import? "build/just/assess.just"

# ═══════════════════════════════════════════════════════════════════════════════
# BUILD & COMPILE
# ═══════════════════════════════════════════════════════════════════════════════

# Build the project: Zig execution host (incl. WASI check modules) + Elixir.
build *args:
    @echo "Building {{project}} (Zig host + Elixir control plane)..."
    zig build {{args}}
    cd bag && mix compile
    @echo "Build complete"

# Build in release mode: optimised Zig host + Elixir release.
build-release *args:
    @echo "Building {{project}} (release)..."
    zig build -Doptimize=ReleaseSafe {{args}}
    cd bag && MIX_ENV=prod mix compile
    @echo "Release build complete (run `just release` to assemble the OTP release)"

# Build only the WASI check modules into zig-out/lib/.
build-wasm:
    zig build wasm

# Clean build artifacts [reversible: rebuild with `just build`].
# NOTE: deliberately does NOT touch build/ — that holds estate machinery
# (build/contractile.just and the imported build/just/*.just), not artifacts.
clean:
    @echo "Cleaning build artifacts..."
    rm -rf zig-out bag/_build verification/proofs/build

# Deep clean including the Zig cache [reversible: rebuild].
clean-all: clean
    rm -rf .zig-cache

# ═══════════════════════════════════════════════════════════════════════════════
# TEST & QUALITY
# ═══════════════════════════════════════════════════════════════════════════════

# Run all tests: Zig unit tests + Elixir suite + Idris typecheck.
test *args:
    zig build test {{args}}
    cd bag && mix test {{args}}
    cd verification/proofs && idris2 --typecheck bag.ipkg

# Run the Elixir suite with detailed (trace) output.
test-verbose:
    cd bag && mix test --trace

# Smoke test: the Zig host responds and lists the estate roster.
test-smoke: build
    ./zig-out/bin/bag_of_actions nodes

# Run the end-to-end demo: freeze a check on owned compute, thaw it, reject a
# tamper (0 GitHub Actions minutes).
e2e: build
    ./scripts/ci-baton-demo.sh

# Run aspect tests (cross-cutting architectural invariants):
#   - the Idris verified ABI still typechecks (spec well-typed),
#   - the three estate manifests agree (just estate-sync),
#   - formatting is clean (zig fmt + mix format).
aspect: typecheck estate-sync fmt-check
    @echo "Aspect invariants hold"

# Benchmarks: not yet configured for this project.
bench:
    @echo "No benchmark suite configured for {{project}} yet."

# Readiness tests: not yet configured for this project.
readiness:
    @echo "No readiness suite configured for {{project}} yet."

# Print the current CRG grade (reads from READINESS.md '**Current Grade:** X' line)
crg-grade:
    @grade=$$(grep -oP '(?<=\*\*Current Grade:\*\* )[A-FX]' READINESS.md 2>/dev/null | head -1); \
    [ -z "$$grade" ] && grade="X"; \
    echo "$$grade"

# Print a shields.io CRG badge for embedding in README files
# Looks for '**Current Grade:** X' in READINESS.md; falls back to X
crg-badge:
    @grade=$$(grep -oP '(?<=\*\*Current Grade:\*\* )[A-FX]' READINESS.md 2>/dev/null | head -1); \
    [ -z "$$grade" ] && grade="X"; \
    case "$$grade" in \
      A) color="brightgreen" ;; \
      B) color="green" ;; \
      C) color="yellow" ;; \
      D) color="orange" ;; \
      E) color="red" ;; \
      F) color="critical" ;; \
      *) color="lightgrey" ;; \
    esac; \
    echo "[![CRG $$grade](https://img.shields.io/badge/CRG-$$grade-$$color?style=flat-square)](https://github.com/hyperpolymath/standards/tree/main/component-readiness-grades)"

# Run the full merge-requirement test suite (ALL categories)
# Per STANDING rule: P2P + E2E + aspect + execution + lifecycle + bench
test-all: test e2e aspect bench readiness
    @echo "All test categories passed — safe to merge!"

# Run all quality checks
quality: fmt-check lint test
    @echo "All quality checks passed!"

# Fix all auto-fixable issues [reversible: git checkout]
fix: fmt
    @echo "Fixed all auto-fixable issues"

# ═══════════════════════════════════════════════════════════════════════════════
# LINT & FORMAT
# ═══════════════════════════════════════════════════════════════════════════════

# Format all source files [reversible: git checkout]
fmt:
    zig fmt src/ build.zig
    cd bag && mix format

# Check formatting without changes (Zig + Elixir).
fmt-check:
    zig fmt --check src/ build.zig
    cd bag && mix format --check-formatted

# Lint: Elixir warnings-as-errors compile (no credo dependency).
lint:
    cd bag && mix compile --warnings-as-errors

# ═══════════════════════════════════════════════════════════════════════════════
# RUN & EXECUTE
# ═══════════════════════════════════════════════════════════════════════════════

# Run the Zig host CLI (e.g. `just run nodes`, `just run init`).
run *args: build
    ./zig-out/bin/bag_of_actions {{args}}

# Print the estate node list + tropical cost from the single mirrored manifest.
nodes: build
    ./zig-out/bin/bag_of_actions nodes

# Install the Zig host binary to ~/.local/bin.
install: build-release
    @echo "Installing {{project}} to ~/.local/bin..."
    install -Dm755 zig-out/bin/bag_of_actions ~/.local/bin/bag_of_actions

# ═══════════════════════════════════════════════════════════════════════════════
# DEPENDENCIES
# ═══════════════════════════════════════════════════════════════════════════════

# Install/check all dependencies (Elixir; the Zig host is dependency-free).
deps:
    cd bag && mix deps.get
    @echo "All dependencies satisfied"

# Audit dependencies for vulnerabilities
deps-audit:
    @echo "Auditing for vulnerabilities..."
    # TODO: Replace with your audit command
    # Examples:
    #   cargo audit
    #   mix audit
    @command -v trivy >/dev/null && trivy fs --severity HIGH,CRITICAL --quiet . || true
    @echo "Audit complete"

# ═══════════════════════════════════════════════════════════════════════════════
# DOCUMENTATION
# ═══════════════════════════════════════════════════════════════════════════════

# Generate all documentation
docs:
    @mkdir -p docs/generated docs/man
    just cookbook
    just man
    @echo "Documentation generated in docs/"

# Generate justfile cookbook documentation
cookbook:
    #!/usr/bin/env bash
    mkdir -p docs
    OUTPUT="docs/just-cookbook.adoc"
    echo "= {{project}} Justfile Cookbook" > "$OUTPUT"
    echo ":toc: left" >> "$OUTPUT"
    echo ":toclevels: 3" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
    echo "Generated: $(date -Iseconds)" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
    echo "== Recipes" >> "$OUTPUT"
    echo "" >> "$OUTPUT"
    just --list --unsorted | while read -r line; do
        if [[ "$line" =~ ^[[:space:]]+([a-z_-]+) ]]; then
            recipe="${BASH_REMATCH[1]}"
            echo "=== $recipe" >> "$OUTPUT"
            echo "" >> "$OUTPUT"
            echo "[source,bash]" >> "$OUTPUT"
            echo "----" >> "$OUTPUT"
            echo "just $recipe" >> "$OUTPUT"
            echo "----" >> "$OUTPUT"
            echo "" >> "$OUTPUT"
        fi
    done
    echo "Generated: $OUTPUT"

# Generate man page
man:
    #!/usr/bin/env bash
    mkdir -p docs/man
    cat > docs/man/{{project}}.1 << EOF
    .TH {{project}} 1 "$(date +%Y-%m-%d)" "{{version}}" "{{project}} Manual"
    .SH NAME
    {{project}} \- RSR-compliant project
    .SH SYNOPSIS
    .B just
    [recipe] [args...]
    .SH DESCRIPTION
    RSR (Rhodium Standard Repository) project managed with just.
    .SH AUTHOR
    $(git config user.name 2>/dev/null || echo "Author") <$(git config user.email 2>/dev/null || echo "email")>
    EOF
    echo "Generated: docs/man/{{project}}.1"

# ═══════════════════════════════════════════════════════════════════════════════
# CONTAINERS (stapeln ecosystem — Podman + Chainguard Wolfi)
# ═══════════════════════════════════════════════════════════════════════════════

# Initialise container templates — substitute placeholders with project values
container-init:
    #!/usr/bin/env bash
    set -euo pipefail

    if [ ! -d "container" ]; then
        echo "Error: container/ directory not found."
        echo "This repo may not have been created from rsr-template-repo."
        exit 1
    fi

    echo "=== Container Template Initialisation ==="
    echo ""

    # Load RSR defaults if available
    DEFAULTS="${XDG_CONFIG_HOME:-$HOME/.config}/rsr/defaults"
    if [ -f "$DEFAULTS" ]; then
        echo "Loading defaults from $DEFAULTS"
        # shellcheck source=/dev/null
        source "$DEFAULTS"
        echo ""
    fi

    # Prompt for container-specific values
    read -rp "Service name (e.g. my-api) [{{project}}]: " _SERVICE_NAME
    SERVICE_NAME="${_SERVICE_NAME:-{{project}}}"

    read -rp "Primary port [8080]: " _PORT
    PORT="${_PORT:-8080}"

    read -rp "Container registry [ghcr.io/${OWNER:-{{OWNER}}}]: " _REGISTRY
    REGISTRY="${_REGISTRY:-ghcr.io/${OWNER:-{{OWNER}}}}"

    echo ""
    echo "  Service: $SERVICE_NAME"
    echo "  Port:    $PORT"
    echo "  Registry: $REGISTRY"
    echo ""
    read -rp "Proceed? [Y/n] " CONFIRM
    [[ "${CONFIRM:-Y}" =~ ^[Nn] ]] && echo "Aborted." && exit 0

    echo ""
    echo "Replacing container placeholders..."

    # Brace tokens as variables (hex escapes avoid just interpolation)
    LB=$(printf '\x7b\x7b')
    RB=$(printf '\x7d\x7d')

    SED_ARGS=(
        -e "s|${LB}SERVICE_NAME${RB}|${SERVICE_NAME}|g"
        -e "s|${LB}PORT${RB}|${PORT}|g"
        -e "s|${LB}REGISTRY${RB}|${REGISTRY}|g"
    )

    find container/ -type f | while read -r file; do
        if file --brief "$file" | grep -qi 'text\|ascii\|utf'; then
            sed -i "${SED_ARGS[@]}" "$file"
        fi
    done

    echo "Container templates initialised."
    echo ""
    echo "Next steps:"
    echo "  1. Edit container/Containerfile — add your build commands"
    echo "  2. Edit container/entrypoint.sh — set your application binary"
    echo "  3. Review container/compose.toml — adjust services and volumes"
    echo "  4. Build: just container-build"

# Build container image via cerro-torre pipeline
container-build *args:
    #!/usr/bin/env bash
    if [ -f "container/ct-build.sh" ]; then
        cd container && ./ct-build.sh {{args}}
    elif [ -f "container/Containerfile" ]; then
        podman build -t {{project}}:latest -f container/Containerfile .
    elif [ -f "build/Containerfile" ]; then
        podman build -t {{project}}:latest -f build/Containerfile .
    elif [ -f "Containerfile" ]; then
        podman build -t {{project}}:latest -f Containerfile .
    else
        echo "No Containerfile found in container/, build/, or project root"
        exit 1
    fi

# Verify compose configuration
container-verify:
    #!/usr/bin/env bash
    if [ ! -f "container/compose.toml" ]; then
        echo "No container/compose.toml found"
        exit 1
    fi
    cd container
    if command -v selur-compose &>/dev/null; then
        selur-compose verify
    else
        echo "selur-compose not found, falling back to podman compose"
        podman compose --file compose.toml config
    fi

# Start container stack
container-up *args:
    #!/usr/bin/env bash
    if [ ! -f "container/compose.toml" ]; then
        echo "No container/compose.toml found"
        exit 1
    fi
    cd container
    if command -v selur-compose &>/dev/null; then
        selur-compose up {{args}}
    else
        podman compose --file compose.toml up {{args}}
    fi

# Stop container stack
container-down:
    #!/usr/bin/env bash
    cd container 2>/dev/null || { echo "No container/ directory"; exit 1; }
    if command -v selur-compose &>/dev/null; then
        selur-compose down
    else
        podman compose --file compose.toml down
    fi

# Sign and verify container bundle (build + pack + sign + verify)
container-sign:
    #!/usr/bin/env bash
    if [ -f "container/ct-build.sh" ]; then
        cd container && ./ct-build.sh
    else
        echo "No container/ct-build.sh found"
        exit 1
    fi

# Push signed bundle to registry
container-push:
    #!/usr/bin/env bash
    if [ -f "container/ct-build.sh" ]; then
        cd container && ./ct-build.sh --push
    else
        echo "No container/ct-build.sh found — falling back to podman push"
        podman push {{project}}:latest
    fi

# Run container interactively (for debugging)
container-run *args:
    podman run --rm -it {{project}}:latest {{args}}

# ═══════════════════════════════════════════════════════════════════════════════
# CI & AUTOMATION
# ═══════════════════════════════════════════════════════════════════════════════

# Run full CI pipeline locally
ci: deps quality
    @echo "CI pipeline complete!"

# Install git hooks
install-hooks:
    @mkdir -p .git/hooks
    @cat > .git/hooks/pre-commit << 'HOOKEOF'
    #!/bin/bash
    just fmt-check || exit 1
    just lint || exit 1
    just assail || exit 1
    HOOKEOF
    @chmod +x .git/hooks/pre-commit
    @echo "Git hooks installed"

# ═══════════════════════════════════════════════════════════════════════════════
# SECURITY
# ═══════════════════════════════════════════════════════════════════════════════

# Run security audit
security: deps-audit
    @echo "=== Security Audit ==="
    @command -v trivy >/dev/null && trivy fs --severity HIGH,CRITICAL . || true
    @echo "Security audit complete"

# Generate SBOM
sbom:
    @mkdir -p docs/security
    @command -v syft >/dev/null && syft . -o spdx-json > docs/security/sbom.spdx.json || echo "syft not found"

# ═══════════════════════════════════════════════════════════════════════════════
# VALIDATION & COMPLIANCE — see build/just/validate.just
# ═══════════════════════════════════════════════════════════════════════════════

import? "build/just/validate.just"

# ═══════════════════════════════════════════════════════════════════════════════
# STATE MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════════

# Update STATE.a2ml timestamp
state-touch:
    @if [ -f ".machine_readable/STATE.a2ml" ]; then \
        sed -i 's/last-updated = "[^"]*"/last-updated = "'"$(date +%Y-%m-%d)"'"/' .machine_readable/STATE.a2ml && \
        echo "STATE.a2ml timestamp updated"; \
    fi

# Show current phase from STATE.a2ml
state-phase:
    @grep -oP 'phase\s*=\s*"\K[^"]+' .machine_readable/STATE.a2ml 2>/dev/null | head -1 || echo "unknown"

# ═══════════════════════════════════════════════════════════════════════════════
# GUIX  (Guix is the sole estate package manager — Guix is banned)
# ═══════════════════════════════════════════════════════════════════════════════

# Enter the Guix development shell.
guix-shell:
    guix shell -D -f guix.scm

# Build with Guix.
guix-build:
    guix build -f guix.scm

# ═══════════════════════════════════════════════════════════════════════════════
# HYBRID AUTOMATION
# ═══════════════════════════════════════════════════════════════════════════════

# Run local automation tasks
automate task="all":
    #!/usr/bin/env bash
    case "{{task}}" in
        all) just fmt && just lint && just test && just docs && just state-touch ;;
        cleanup) just clean && find . -name "*.orig" -delete && find . -name "*~" -delete ;;
        update) just deps && just validate ;;
        *) echo "Unknown: {{task}}. Use: all, cleanup, update" && exit 1 ;;
    esac

# ═══════════════════════════════════════════════════════════════════════════════
# COMBINATORIC MATRIX RECIPES
# ═══════════════════════════════════════════════════════════════════════════════

# Build matrix: [debug|release] x [target] x [features]
build-matrix mode="debug" target="" features="":
    @echo "Build matrix: mode={{mode}} target={{target}} features={{features}}"

# Test matrix: [unit|integration|e2e|all] x [verbosity] x [parallel]
test-matrix suite="unit" verbosity="normal" parallel="true":
    @echo "Test matrix: suite={{suite}} verbosity={{verbosity}} parallel={{parallel}}"

# Container matrix: [build|run|push|shell|scan] x [registry] x [tag]
container-matrix action="build" registry="ghcr.io/{{OWNER}}" tag="latest":
    @echo "Container matrix: action={{action}} registry={{registry}} tag={{tag}}"

# CI matrix: [lint|test|build|security|all] x [quick|full]
ci-matrix stage="all" depth="quick":
    @echo "CI matrix: stage={{stage}} depth={{depth}}"

# Show all matrix combinations
combinations:
    @echo "=== Combinatoric Matrix Recipes ==="
    @echo ""
    @echo "Build Matrix: just build-matrix [debug|release] [target] [features]"
    @echo "Test Matrix:  just test-matrix [unit|integration|e2e|all] [verbosity] [parallel]"
    @echo "Container:    just container-matrix [build|run|push|shell|scan] [registry] [tag]"
    @echo "CI Matrix:    just ci-matrix [lint|test|build|security|all] [quick|full]"

# ═══════════════════════════════════════════════════════════════════════════════
# VERSION CONTROL
# ═══════════════════════════════════════════════════════════════════════════════

# Show git status
status:
    @git status --short

# Show recent commits
log count="20":
    @git log --oneline -{{count}}

# Generate CHANGELOG.md with git-cliff
changelog:
    @command -v git-cliff >/dev/null || { echo "git-cliff not found — install: cargo install git-cliff"; exit 1; }
    git cliff --config .machine_readable/configs/git-cliff/cliff.toml --output CHANGELOG.md
    @echo "Generated CHANGELOG.md"

# Preview changelog for unreleased commits (does not write)
changelog-preview:
    @command -v git-cliff >/dev/null || { echo "git-cliff not found — install: cargo install git-cliff"; exit 1; }
    git cliff --config .machine_readable/configs/git-cliff/cliff.toml --unreleased --strip header

# Tag a new release (usage: just release-tag 1.2.3)
release-tag version:
    #!/usr/bin/env bash
    TAG="v{{version}}"
    if git rev-parse "$TAG" >/dev/null 2>&1; then
        echo "Tag $TAG already exists"
        exit 1
    fi
    just changelog
    git add CHANGELOG.md
    git commit -m "chore(release): prepare $TAG"
    git tag -a "$TAG" -m "Release $TAG"
    echo "Created tag $TAG — push with: git push origin main --tags"

# ═══════════════════════════════════════════════════════════════════════════════
# RELEASE & ESTATE INTEGRITY
# ═══════════════════════════════════════════════════════════════════════════════

# Assemble a self-contained, fail-closed Elixir release (MIX_ENV=prod).
# Boot refuses to start without a real BAG_ATTEST_KEY/GH_TOKEN/BAG_STATE_DIR
# (see Bag.Config.validate!/0, gated to :prod in config/runtime.exs).
release: build-release
    cd bag && MIX_ENV=prod mix release --overwrite
    @echo "Release assembled at bag/_build/prod/rel/bag"

# estate-sync — the manual-sync footgun guard.
# Verify the three estate manifests agree on the node roster:
#   verification/proofs/Bag/Estate.idr  (formal ground truth)
#   src/estate.zig                       (Zig host mirror)
#   nodes.scm                            (Guix-native mirror)
# Exits non-zero (with a diff) if any manifest lists a different set of nodes.
estate-sync:
    #!/usr/bin/env bash
    set -euo pipefail
    idr=$(grep -oP 'MkNode "\K[^"]+' verification/proofs/Bag/Estate.idr | sort -u)
    zig=$(grep -oP '\.name = "\Kmesh-[^"]+' src/estate.zig | sort -u)
    scm=$(grep -oP '\(name \. "\Kmesh-[^"]+' nodes.scm | sort -u)
    echo "Estate roster ($(echo "$idr" | wc -l) nodes):"; echo "$idr" | sed 's/^/  /'
    fail=0
    if [ "$idr" != "$zig" ]; then
        echo "DRIFT: src/estate.zig roster differs from Estate.idr"
        diff <(echo "$idr") <(echo "$zig") || true; fail=1
    fi
    if [ "$idr" != "$scm" ]; then
        echo "DRIFT: nodes.scm roster differs from Estate.idr"
        diff <(echo "$idr") <(echo "$scm") || true; fail=1
    fi
    [ "$fail" -eq 0 ] && echo "OK: all three estate manifests agree" \
        || { echo "Reconcile the manifests before release."; exit 1; }

# version — document (do NOT change) the four files that carry the release
# version and must be kept in agreement by hand. Prints the current value of
# each so drift is visible. Keep this list in step with any version bump.
version:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "Version-bearing files to keep in sync (current values):"
    printf '  %-34s %s\n' "Justfile (version :=)"       "{{version}}"
    printf '  %-34s %s\n' "bag/mix.exs"                 "$(grep -oP 'version:\s*"\K[^"]+' bag/mix.exs | head -1)"
    printf '  %-34s %s\n' "build.zig.zon"               "$(grep -oP '\.version\s*=\s*"\K[^"]+' build.zig.zon | head -1)"
    printf '  %-34s %s\n' "nodes.scm (header)"          "$(grep -oP ';;\s*[Vv]ersion:\s*\K\S+' nodes.scm | head -1 || echo '(no version line)')"
    printf '  %-34s %s\n' ".machine_readable/6a2/STATE.a2ml" "$(grep -oP 'version\s*=\s*"\K[^"]+' .machine_readable/6a2/STATE.a2ml | head -1)"
    echo "(This recipe is read-only — bump versions by hand, then re-run to confirm.)"

# ═══════════════════════════════════════════════════════════════════════════════
# UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

# Count lines of code
loc:
    @find . \( -name "*.rs" -o -name "*.ex" -o -name "*.exs" -o -name "*.res" -o -name "*.gleam" -o -name "*.zig" -o -name "*.idr" -o -name "*.hs" -o -name "*.ncl" -o -name "*.scm" -o -name "*.adb" -o -name "*.ads" \) -not -path './target/*' -not -path './_build/*' 2>/dev/null | xargs wc -l 2>/dev/null | tail -1 || echo "0"

# Show TODO comments
todos:
    @grep -rn "TODO\|FIXME\|HACK\|XXX" --include="*.rs" --include="*.ex" --include="*.res" --include="*.gleam" --include="*.zig" --include="*.idr" --include="*.hs" . 2>/dev/null || echo "No TODOs"

# Open in editor
edit:
    ${EDITOR:-code} .

# Run high-rigor security assault using panic-attacker
maint-assault:
    @./.machine_readable/scripts/maintenance/maint-assault.sh

# Run panic-attacker pre-commit scan (foundational floor-raise requirement)
assail:
    @command -v panic-attack >/dev/null 2>&1 && panic-attack assail . || echo "WARN: panic-attack not found — install from https://github.com/hyperpolymath/panic-attacker"


# Self-diagnostic — checks the toolchain this project needs.
doctor:
    @echo "Running diagnostics for {{project}}..."
    @echo "Checking required tools..."
    @command -v just   >/dev/null 2>&1 && echo "  [OK] just"   || echo "  [FAIL] just not found"
    @command -v git    >/dev/null 2>&1 && echo "  [OK] git"    || echo "  [FAIL] git not found"
    @command -v zig    >/dev/null 2>&1 && echo "  [OK] zig"    || echo "  [FAIL] zig not found"
    @command -v elixir >/dev/null 2>&1 && echo "  [OK] elixir" || echo "  [FAIL] elixir not found"
    @command -v idris2 >/dev/null 2>&1 && echo "  [OK] idris2" || echo "  [WARN] idris2 not found (needed for the verified ABI)"
    @echo "Diagnostics complete."

# Guided tour of key features
tour:
    @echo "=== {{project}} Tour ==="
    @echo ""
    @echo "1. Project structure:"
    @ls -la
    @echo ""
    @echo "2. Available commands: just --list"
    @echo ""
    @echo "3. Read README.adoc for full overview"
    @echo "4. Read EXPLAINME.adoc for architecture decisions"
    @echo "5. Run 'just doctor' to check your setup"
    @echo ""
    @echo "Tour complete! Try 'just --list' to see all available commands."

# Open feedback channel with diagnostic context
help-me:
    @echo "=== {{project}} Help ==="
    @echo "Platform: $(uname -s) $(uname -m)"
    @echo "Shell: $SHELL"
    @echo ""
    @echo "To report an issue:"
    @echo "  https://github.com/{{OWNER}}/{{REPO}}/issues/new"
    @echo ""
    @echo "Include the output of 'just doctor' in your report."

# ═══════════════════════════════════════════════════════════════════════════════
# FORMAL VERIFICATION (PROOFS) — see build/just/proofs.just
# ═══════════════════════════════════════════════════════════════════════════════

import? "build/just/proofs.just"

# Typecheck the Idris 2 verified ABI (the formal spec must stay well-typed).
typecheck:
    cd verification/proofs && idris2 --typecheck bag.ipkg

# ═══════════════════════════════════════════════════════════════════════════════
# SESSION MANAGEMENT (THIN BINDINGS TO CENTRAL STANDARDS)
# ═══════════════════════════════════════════════════════════════════════════════

# Show canonical session-management command model
session-help:
    @echo "Canonical command model:"
    @echo "  intake repo <path>"
    @echo "  checkpoint change <path>"
    @echo "  verify maintenance <path>"
    @echo "  verify substantial <path>"
    @echo "  verify release <path>"
    @echo "  close planned <path>"
    @echo "  close urgent <path>"
    @echo "  recover repo <path>"
    @echo "  handover full <path>"
    @echo "  handover split <path>"
    @echo "  handover model <path>"
    @echo "  handover human <path>"
    @echo ""
    @echo "Use Just aliases below (thin wrappers around ./session/dispatch.sh)."

# Canonical aliases (friendly recipe names that map to canonical commands)
intake-repo path=".":
    @./session/dispatch.sh intake repo "{{path}}"

checkpoint-change path=".":
    @./session/dispatch.sh checkpoint change "{{path}}"

verify-maintenance path=".":
    @./session/dispatch.sh verify maintenance "{{path}}"

verify-substantial path=".":
    @./session/dispatch.sh verify substantial "{{path}}"

verify-release path=".":
    @./session/dispatch.sh verify release "{{path}}"

close-planned path=".":
    @./session/dispatch.sh close planned "{{path}}"

close-urgent path=".":
    @./session/dispatch.sh close urgent "{{path}}"

recover-repo path=".":
    @./session/dispatch.sh recover repo "{{path}}"

handover-full path=".":
    @./session/dispatch.sh handover full "{{path}}"

handover-split path=".":
    @./session/dispatch.sh handover split "{{path}}"

handover-model path=".":
    @./session/dispatch.sh handover model "{{path}}"

handover-human path=".":
    @./session/dispatch.sh handover human "{{path}}"

secret-scan-trufflehog:
    @command -v trufflehog >/dev/null && trufflehog filesystem . --only-verified || true
