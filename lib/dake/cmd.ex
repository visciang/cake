defprotocol Dake.Cmd do
  @type result :: :ok | {:ignore, reason :: term()} | {:error, reason :: term()} | :timeout

  @spec exec(t(), Dake.Parser.Dakefile.t(), Dake.Dag.graph()) :: result()
  def exec(cmd, dakefile, graph)
end
