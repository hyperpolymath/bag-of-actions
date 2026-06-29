# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.MixProject do
  use Mix.Project

  def project do
    [
      app: :bag,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  # `mix release` packaging. The control-plane ships as a self-contained release
  # whose boot-time env validation is fail-closed (see config/runtime.exs →
  # Bag.Config.validate!/1). ERTS is bundled so the target needs no system
  # Erlang; quiet-included applications start with the release.
  defp releases do
    [
      bag: [
        include_executables_for: [:unix],
        include_erts: true,
        applications: [bag: :permanent]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Bag.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
