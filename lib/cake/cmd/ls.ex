defimpl Cake.Cmd, for: Cake.Cli.Ls do
  alias Cake.{Dag, Dir, Type}
  alias Cake.Cli.Ls
  alias Cake.Parser.Cakefile
  alias Cake.Parser.Container.Arg
  alias Cake.Parser.Directive.{DevShell, Output}
  alias Cake.Parser.{Alias, Target}

  @builtin_docker_args [
    "TARGETPLATFORM",
    "TARGETOS",
    "TARGETARCH",
    "TARGETVARIANT",
    "BUILDPLATFORM",
    "BUILDOS",
    "BUILDARCH",
    "BUILDVARIANT"
  ]

  @spec exec(Ls.t(), Cakefile.t(), Dag.graph()) :: :ok
  def exec(%Ls{}, %Cakefile{} = cakefile, _graph) do
    Dir.setup_cake_dirs()

    global_args = cakefile.args
    targets = cakefile.targets |> Enum.sort_by(& &1.tgid)
    target_args = target_args(cakefile)
    target_outputs = target_outputs(cakefile)
    devshell_targets = devshell_targets(cakefile)

    if global_args != [] do
      IO.puts("\nGlobal arguments:")

      for arg <- global_args,
          not hidden_arg(arg.name),
          do: IO.ANSI.format_fragment(["  ", fmt_arg(arg), "\n"]) |> IO.write()
    end

    IO.puts("\nAliases:")

    for %Alias{tgid: tgid, tgids: tgids} <- targets do
      alias_ = ["  ", :green, tgid, ": ", :faint, Enum.join(tgids, " "), "\n", :reset]

      IO.ANSI.format(alias_) |> IO.write()
    end

    IO.puts("\nTargets:")

    for %Target{tgid: tgid} <- targets do
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

  @spec hidden_arg(String.t()) :: boolean()
  defp hidden_arg(name) do
    String.starts_with?(name, "_") or name in @builtin_docker_args
  end

  @spec target_args(Cakefile.t()) :: %{Type.tgid() => [Arg.t()]}
  defp target_args(%Cakefile{} = cakefile) do
    for %Target{} = target <- cakefile.targets, into: %{} do
      {target.tgid, for(%Arg{} = arg <- target.commands, not hidden_arg(arg.name), do: arg)}
    end
  end

  @spec target_outputs(Cakefile.t()) :: %{Type.tgid() => [Output.t()]}
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
