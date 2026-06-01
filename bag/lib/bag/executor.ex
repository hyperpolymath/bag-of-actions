# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.Executor do
  @moduledoc """
  Interfaces with the Zig-based continuation runner.
  """
  alias Bag.Baton

  @executor_path Path.expand("../../../zig-out/bin/bag_of_actions", __DIR__)

  @doc """
  Runs a single step of the Baton.
  """
  def execute(%Baton{} = baton) do
    # 1. Prepare the baton file for the Zig host
    save_baton_to_disk(baton)

    # 2. Run the Zig executor
    case System.cmd(@executor_path, ["run"], cd: Path.expand("../../../", __DIR__)) do
      {output, 0} ->
        # 3. Reload the updated baton from disk
        updated_baton = load_baton_from_disk()
        {:ok, updated_baton, output}

      {error, _code} ->
        {:error, error}
    end
  end

  defp save_baton_to_disk(baton) do
    # Matches the format expected by our Zig Milestone 1/3 host
    pkg = baton.guix_package || "none"
    content = "#{baton.counter}\n#{baton.module_cid}\n#{pkg}\n"
    File.write!(Path.expand("../../../baton.txt", __DIR__), content)
  end

  defp load_baton_from_disk() do
    content = File.read!(Path.expand("../../../baton.txt", __DIR__))
    [counter_str, module_cid, pkg_line | _] = String.split(content, "\n", trim: true)
    
    %Baton{
      counter: String.to_integer(counter_str),
      module_cid: module_cid,
      guix_package: if(pkg_line == "none", do: nil, else: pkg_line),
      status: :floating
    }
  end
end
