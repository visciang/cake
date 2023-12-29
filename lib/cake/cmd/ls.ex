defimpl Cake.Cmd, for: Cake.Cli.Ls do
  alias Cake.Cli.Ls
  alias Cake.{Dag, Dir, Type}
  alias Cake.Parser.Cakefile
  alias Cake.Parser.Container.Arg
  alias Cake.Parser.Target

  @typep target_args :: %{Type.tgid() => [Arg.t()]}

  @spec exec(Ls.t(), Cakefile.t(), Dag.graph()) :: :ok
  def exec(%Ls{}, %Cakefile{} = cakefile, graph) do
    Dir.setup_cake_dirs()

    global_args = cakefile.args
    target_args = target_args(cakefile)

    if global_args != [] do
      IO.puts("\nGlobal arguments:")

      for arg <- global_args,
          do: IO.puts(" - #{fmt_arg(arg)}")
    end

    IO.puts("\nTargets:")

    for tgid <- Dag.tgids(graph) |> Enum.sort(),
        do: IO.puts(" - #{fmt_target(tgid, target_args)}")

    :ok
  end

  @spec target_args(Cakefile.t()) :: target_args()
  defp target_args(%Cakefile{} = cakefile) do
    for %Target{} = target <- cakefile.targets, into: %{} do
      {target.tgid, for(%Arg{} = arg <- target.commands, do: arg)}
    end
  end

  @spec fmt_arg(Arg.t()) :: String.t()
  defp fmt_arg(%Arg{default_value: nil} = arg), do: arg.name
  defp fmt_arg(%Arg{} = arg), do: "#{arg.name}=#{inspect(arg.default_value)}"

  @spec fmt_target(Type.tgid(), target_args()) :: IO.chardata()
  defp fmt_target(tgid, target_args) do
    args = Map.get(target_args, tgid, [])
    args = Enum.map_join(args, ", ", &fmt_arg(&1))

    IO.ANSI.format([:green, tgid, :default_color, "  ", args])
  end
end
