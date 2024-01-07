defimpl Cake.Cmd, for: Cake.Cli.Ls do
  alias Cake.Cli.Ls
  alias Cake.{Dag, Dir, Type}
  alias Cake.Parser.Cakefile
  alias Cake.Parser.Container.Arg
  alias Cake.Parser.Directive.DevShell
  alias Cake.Parser.Target

  @typep target_args :: %{Type.tgid() => [Arg.t()]}

  @spec exec(Ls.t(), Cakefile.t(), Dag.graph()) :: :ok
  def exec(%Ls{}, %Cakefile{} = cakefile, graph) do
    Dir.setup_cake_dirs()

    global_args = cakefile.args
    target_args = target_args(cakefile)
    devshell_targets = devshell_targets(cakefile)

    if global_args != [] do
      IO.puts("\nGlobal arguments:")

      for arg <- global_args,
          do: IO.puts(" - #{fmt_arg(arg)}")
    end

    IO.puts("\nTargets:")

    for tgid <- Dag.tgids(graph) |> Enum.sort() do
      devshell? = MapSet.member?(devshell_targets, tgid)
      IO.puts(" - #{fmt_target(tgid, target_args, devshell?)}")
    end

    :ok
  end

  @spec target_args(Cakefile.t()) :: target_args()
  defp target_args(%Cakefile{} = cakefile) do
    for %Target{} = target <- cakefile.targets, into: %{} do
      {target.tgid, for(%Arg{} = arg <- target.commands, do: arg)}
    end
  end

  @spec devshell_targets(Cakefile.t()) :: MapSet.t(Type.tgid())
  defp devshell_targets(%Cakefile{} = cakefile) do
    for %Target{} = target <- cakefile.targets,
        Enum.any?(target.directives, &match?(%DevShell{}, &1)),
        into: MapSet.new() do
      target.tgid
    end
  end

  @spec fmt_arg(Arg.t()) :: String.t()
  defp fmt_arg(%Arg{default_value: nil} = arg), do: arg.name
  defp fmt_arg(%Arg{} = arg), do: "#{arg.name}=#{inspect(arg.default_value)}"

  @spec fmt_target(Type.tgid(), target_args(), devshell? :: boolean()) :: IO.chardata()
  defp fmt_target(tgid, target_args, devshell?) do
    devshell_str = if devshell?, do: [:blue, " [devshell]", :reset], else: ""
    args = Map.get(target_args, tgid, [])
    args = Enum.map_join(args, ", ", &fmt_arg(&1))

    IO.ANSI.format_fragment([:green, tgid, :reset, devshell_str, "  ", args])
  end
end
