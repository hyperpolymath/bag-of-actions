# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Bag.Baton do
  @moduledoc """
  The mobile unit of work.
  """
  defstruct [:id, :counter, :module_cid, :guix_package, :status]

  @type t :: %__MODULE__{
          id: String.t(),
          counter: integer(),
          module_cid: String.t(),
          guix_package: String.t() | nil,
          status: :floating | :executing | :completed
        }

  def new(counter \\ 0, module_cid \\ "counter.wat", guix_package \\ "hello") do
    %__MODULE__{
      id: "baton-" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)),
      counter: counter,
      module_cid: module_cid,
      guix_package: guix_package,
      status: :floating
    }
  end
end
