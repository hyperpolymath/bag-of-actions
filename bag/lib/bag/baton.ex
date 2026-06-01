# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.Baton do
  @moduledoc """
  The mobile unit of work.
  """
  defstruct [:id, :counter, :module_cid, :guix_package, :required_cap, :status]

  @type t :: %__MODULE__{
          id: String.t(),
          counter: integer(),
          module_cid: String.t(),
          guix_package: String.t() | nil,
          required_cap: [atom()],
          status: :floating | :executing | :completed
        }

  def new(counter \\ 0, module_cid \\ "counter.wat", guix_package \\ "hello", required_cap \\ [:guix]) do
    %__MODULE__{
      id: "baton-" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)),
      counter: counter,
      module_cid: module_cid,
      guix_package: guix_package,
      required_cap: required_cap,
      status: :floating
    }
  end
end
