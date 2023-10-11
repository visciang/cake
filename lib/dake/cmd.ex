defprotocol Dake.Cmd do
  @type result :: :ok | {:error, reason :: term()}

  @spec exec(t(), Dake.Parser.Dakefile.t(), Dake.Dag.graph()) :: result()
  def exec(cmd, dakefile, graph)
end
