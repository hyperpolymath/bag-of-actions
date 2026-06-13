# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# Dogfood CI manifest: bag-of-actions' OWN checks, run as Batons on owned
# compute (zero GitHub Actions minutes). Consumed by `mix bag.sweep` and, in
# turn, by hypatia/ci-health. Each entry: check_id, command (argv), required_cap.
[
  %{
    check_id: "zig-fmt",
    command: ["zig", "fmt", "--check", "build.zig", "src/root.zig"],
    required_cap: "zig"
  },
  %{
    check_id: "zig-build-test",
    command: ["zig", "build", "test"],
    required_cap: "zig"
  }
]
