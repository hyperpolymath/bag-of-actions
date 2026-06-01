# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.Executor do
  @moduledoc """
  Interfaces with the Zig-based continuation runner.
  """
  alias Bag.Baton

  @executor_path Path.expand("../../../zig-out/bin/bag_of_actions", __DIR__)

  @doc """
  Checks if a node satisfies the required capabilities using the Idris-to-Zig bridge.
  """
  def node_satisfies?(node_name, requirements) do
    args = ["match", node_name | requirements]

    case System.cmd(@executor_path, args, cd: Path.expand("../../../", __DIR__)) do
      {_output, 0} -> true
      {_output, _code} -> false
    end
  end

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
    # Serialize requirements to a comma-separated string for the text file
    caps = if baton.required_cap == [], do: "none", else: Enum.join(baton.required_cap, ",")
    content = "#{baton.counter}\n#{baton.module_cid}\n#{pkg}\n#{caps}\n"
    File.write!(Path.expand("../../../baton.txt", __DIR__), content)
  end

  defp load_baton_from_disk() do
    content = File.read!(Path.expand("../../../baton.txt", __DIR__))
    [counter_str, module_cid, pkg_line, caps_line | _] = String.split(content, "\n", trim: true)
    
    required_cap = 
      if caps_line == "none" do
        []
      else
        caps_line |> String.split(",") |> Enum.map(&String.to_existing_atom/1)
      end

    %Baton{
      counter: String.to_integer(counter_str),
      module_cid: module_cid,
      guix_package: if(pkg_line == "none", do: nil, else: pkg_line),
      required_cap: required_cap,
      status: :floating
    }
  end
end
