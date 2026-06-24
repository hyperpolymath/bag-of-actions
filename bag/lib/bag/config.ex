# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.Config do
  @moduledoc """
  Boot-time configuration access and **fail-closed** validation.

  `validate!/0` enforces that a production node is fully configured before it is
  allowed to run: a missing required secret raises with a clear message rather
  than letting the node start in a half-configured (e.g. dev-placeholder-key)
  state. It is invoked **only on the production/release boot path** — see the
  `config_env() == :prod` guard in `config/runtime.exs`. It is never called under
  `:test`/`:dev`, so `mix test` and plain `mix run` work with no env vars set.

  Values are surfaced into `:bag` application config by `runtime.exs` from the
  environment, so the rest of the app reads a single source of truth via the
  accessors here instead of scattering `System.get_env/1` calls.
  """

  # The dev placeholder the Zig host falls back to when BAG_ATTEST_KEY is unset.
  # A :prod node carrying this value is treated as unconfigured (fail closed).
  @dev_placeholder_key "bag-of-actions-dev-key"

  # Minimum acceptable real key length, to catch empty/trivial values in prod.
  @min_key_len 16

  @doc "The HMAC attestation key (`BAG_ATTEST_KEY`), or `nil` if unset."
  @spec attest_key() :: String.t() | nil
  def attest_key, do: get(:attest_key)

  @doc "The ed25519 signing key path (`BAG_SIGN_KEY_PATH`), or `nil` if unset."
  @spec sign_key_path() :: String.t() | nil
  def sign_key_path, do: get(:sign_key_path)

  @doc "The GitHub token (`GH_TOKEN`) used to post commit statuses, or `nil`."
  @spec gh_token() :: String.t() | nil
  def gh_token, do: get(:gh_token)

  @doc "The directory where frozen Baton state is written (`BAG_STATE_DIR`), or `nil`."
  @spec state_dir() :: String.t() | nil
  def state_dir, do: get(:state_dir)

  @doc """
  Resolve the Zig host executable path. Prefers `:bag, :executor_path`
  (from `BAG_BIN`), falling back to the in-tree build output. Returns an
  absolute path; existence is checked separately by `validate!/0`.
  """
  @spec executor_path() :: String.t()
  def executor_path do
    case get(:executor_path) do
      blank when blank in [nil, ""] -> Path.expand("../../../zig-out/bin/bag_of_actions", __DIR__)
      path -> Path.expand(path)
    end
  end

  @doc """
  Validate the production environment, raising on any fatal misconfiguration.

  Intended to run **only** on the prod/release boot path (gated in
  `config/runtime.exs`). It requires, and aborts boot if any is missing or
  obviously a placeholder:

    * `BAG_ATTEST_KEY` — present, not the dev placeholder, >= #{@min_key_len} bytes.
    * `GH_TOKEN` — present (needed to report verdicts as commit statuses).
    * `BAG_STATE_DIR` — present and an existing, writable directory.
    * the Zig host binary — present at `executor_path/0`.

  `BAG_SIGN_KEY_PATH` is optional, but if set the file must exist (a path that
  points at nothing is a configuration error, not a silent HMAC-only fallback).

  Returns `:ok` on success.
  """
  @spec validate!() :: :ok
  def validate! do
    errors =
      []
      |> require_secret(:attest_key, "BAG_ATTEST_KEY")
      |> reject_placeholder_key()
      |> require_secret(:gh_token, "GH_TOKEN")
      |> check_state_dir()
      |> check_executor()
      |> check_sign_key_path()

    case Enum.reverse(errors) do
      [] ->
        :ok

      problems ->
        raise """
        Bag.Config: refusing to boot — #{length(problems)} configuration problem(s):

        #{problems |> Enum.map(&("  - " <> &1)) |> Enum.join("\n")}

        Set the required environment variables (BAG_ATTEST_KEY, GH_TOKEN, \
        BAG_STATE_DIR, and optionally BAG_SIGN_KEY_PATH) before starting a \
        production node.
        """
    end
  end

  # -- internals --------------------------------------------------------------

  defp get(key), do: Application.get_env(:bag, key)

  defp require_secret(errors, key, env_name) do
    case get(key) do
      blank when blank in [nil, ""] -> ["#{env_name} is unset" | errors]
      _ -> errors
    end
  end

  defp reject_placeholder_key(errors) do
    case attest_key() do
      @dev_placeholder_key ->
        ["BAG_ATTEST_KEY is the documented dev placeholder — set a real secret in :prod" | errors]

      key when is_binary(key) and byte_size(key) < @min_key_len ->
        ["BAG_ATTEST_KEY is too short (< #{@min_key_len} bytes) to be a real key" | errors]

      _ ->
        errors
    end
  end

  defp check_state_dir(errors) do
    case state_dir() do
      blank when blank in [nil, ""] ->
        ["BAG_STATE_DIR is unset (no directory to write frozen Baton state to)" | errors]

      dir ->
        cond do
          not File.dir?(dir) -> ["BAG_STATE_DIR #{dir} is not an existing directory" | errors]
          not writable?(dir) -> ["BAG_STATE_DIR #{dir} is not writable" | errors]
          true -> errors
        end
    end
  end

  defp check_executor(errors) do
    path = executor_path()

    cond do
      not File.exists?(path) ->
        ["Zig host binary not found at #{path} (run `zig build`, or set BAG_BIN)" | errors]

      not File.regular?(path) ->
        ["BAG_BIN at #{path} is not a regular file" | errors]

      true ->
        errors
    end
  end

  defp check_sign_key_path(errors) do
    case sign_key_path() do
      blank when blank in [nil, ""] ->
        errors

      path ->
        if File.exists?(path),
          do: errors,
          else: ["BAG_SIGN_KEY_PATH set but no file at #{path}" | errors]
    end
  end

  defp writable?(dir) do
    case File.stat(dir) do
      {:ok, %File.Stat{access: access}} when access in [:write, :read_write] -> true
      _ -> false
    end
  end
end
