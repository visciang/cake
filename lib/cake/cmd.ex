defprotocol Cake.Cmd do
  @type result :: {:ok, info :: nil | term()} | :timeout | {:ignore, reason :: term()} | {:error, reason :: term()}

  @spec exec(t(), Cake.Parser.Cakefile.t(), Cake.Dag.graph()) :: result()
  def exec(cmd, cakefile, graph)
end
