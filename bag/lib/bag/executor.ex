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
    # Matches the format expected by our Zig Milestone 1 host
    content = "#{baton.counter}\n#{baton.module_cid}\n"
    File.write!(Path.expand("../../../baton.txt", __DIR__), content)
  end

  defp load_baton_from_disk() do
    content = File.read!(Path.expand("../../../baton.txt", __DIR__))
    [counter_str, module_cid | _] = String.split(content, "\n", trim: true)
    
    %Baton{
      counter: String.to_integer(counter_str),
      module_cid: module_cid,
      status: :floating
    }
  end
end
