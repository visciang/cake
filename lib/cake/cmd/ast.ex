defimpl Cake.Cmd, for: Cake.Cli.Ast do
  alias Cake.{Cmd, Dag}
  alias Cake.Cli.Ast
  alias Cake.Parser.Cakefile

  @spec exec(Ast.t(), Cakefile.t(), Dag.graph()) :: Cmd.result()
  def exec(%Ast{}, %Cakefile{} = cakefile, _graph) do
    {:ok, cakefile}
  end
end
