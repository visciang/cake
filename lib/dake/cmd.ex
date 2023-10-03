defprotocol Dake.Cmd do
  @moduledoc false

  @spec exec(t(), Dake.Parser.Dakefile.t(), Dake.Dag.graph()) :: :ok
  def exec(cmd, dakefile, graph)
end
