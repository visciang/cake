defprotocol Dake.Cmd do
  @moduledoc false

  @spec exec(t(), Dake.Parser.Dakefile.t(), Dake.Dag.graph()) :: :ok
  def exec(cli_args, dakefile, graph)
end
