defimpl Cake.Cmd, for: Cake.Cli.Ls do
  alias Cake.Cli.Ls
  alias Cake.{Dag, Dir, Type}
  alias Cake.Parser.Cakefile
  alias Cake.Parser.Container.Arg
  alias Cake.Parser.Directive.{DevShell, Output}
  alias Cake.Parser.Target

  @typep target_args :: %{Type.tgid() => [Arg.t()]}
  @typep target_outputs :: %{Type.tgid() => [Output.t()]}

  @spec exec(Ls.t(), Cakefile.t(), Dag.graph()) :: :ok
  def exec(%Ls{}, %Cakefile{} = cakefile, graph) do
    Dir.setup_cake_dirs()

    global_args = cakefile.args
    target_args = target_args(cakefile)
    target_outputs = target_outputs(cakefile)
    devshell_targets = devshell_targets(cakefile)

    if global_args != [] do
      IO.puts("\nGlobal arguments:")

      for arg <- global_args,
          do: IO.ANSI.format_fragment(["  ", fmt_arg(arg), "\n"]) |> IO.write()
    end

    IO.puts("\nTargets:")

    for tgid <- Dag.tgids(graph) |> Enum.sort() do
      target = ["  ", :green, tgid, ":", :reset, "\n"]
      devshell? = MapSet.member?(devshell_targets, tgid)
      devshell = if devshell?, do: [:blue, "    @devshell\n", :reset], else: ""

      outputs =
        for output <- Map.get(target_outputs, tgid, []),
            do: [:blue, "    @output ", :faint, output, "\n", :reset]

      args =
        for arg <- Map.get(target_args, tgid, []),
            do: ["    ", fmt_arg(arg), "\n", :reset]

      IO.ANSI.format([target, devshell, outputs, args]) |> IO.write()
    end

    :ok
  end

  @spec target_args(Cakefile.t()) :: target_args()
  defp target_args(%Cakefile{} = cakefile) do
    for %Target{} = target <- cakefile.targets, into: %{} do
      {target.tgid, for(%Arg{} = arg <- target.commands, do: arg)}
    end
  end

  @spec target_outputs(Cakefile.t()) :: target_outputs()
  defp target_outputs(%Cakefile{} = cakefile) do
    for %Target{} = target <- cakefile.targets, into: %{} do
      {target.tgid, for(%Output{} = output <- target.directives, do: output.path)}
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

  @spec fmt_arg(Arg.t()) :: IO.ANSI.ansidata()
  defp fmt_arg(%Arg{default_value: nil} = arg), do: [:blue, arg.name]
  defp fmt_arg(%Arg{} = arg), do: [:blue, arg.name, :faint, "=#{inspect(arg.default_value)}", :reset]
end
