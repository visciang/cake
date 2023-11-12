defprotocol Cake.Cmd do
  @type result :: :ok | {:ignore, reason :: term()} | {:error, reason :: term()} | :timeout

  @spec exec(t(), Cake.Parser.Cakefile.t(), Cake.Dag.graph()) :: result()
  def exec(cmd, cakefile, graph)
end
