defmodule Dake.Cmd.Run do
  @moduledoc """
  run Command.
  """

  alias Dake.Dag
  alias Dake.Parser.Dakefile
  alias Dake.Pipeline

  @spec exec(Dakefile.t(), Dag.graph()) :: :ok
  def exec(dakefile, _graph) do
    Pipeline.build(dakefile)

    :ok
  end
end
