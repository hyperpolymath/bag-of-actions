defmodule Bag.Baton do
  @moduledoc """
  The mobile unit of work.
  """
  defstruct [:id, :counter, :module_cid, :status]

  @type t :: %__MODULE__{
          id: String.t(),
          counter: integer(),
          module_cid: String.t(),
          status: :floating | :executing | :completed
        }

  def new(counter \\ 0, module_cid \\ "counter.wat") do
    %__MODULE__{
      id: "baton-" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)),
      counter: counter,
      module_cid: module_cid,
      status: :floating
    }
  end
end
