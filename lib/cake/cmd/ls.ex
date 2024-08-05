defimpl Cake.Cmd, for: Cake.Cli.Ls do
  alias Cake.{Dag, Dir, Type}
  alias Cake.Cli.Ls
  alias Cake.Parser.Cakefile
  alias Cake.Parser.Directive.{DevShell, Output, When}
  alias Cake.Parser.Target.Container.{Arg, Env}
  alias Cake.Parser.Target.{Alias, Container, Local}

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
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def exec(%Ls{}, %Cakefile{} = cakefile, _graph) do
    Dir.setup_cake_dirs()

    global_args = cakefile.args
    targets = cakefile.targets |> Enum.sort_by(& &1.tgid)
    target_args = target_args(cakefile)
    target_when = target_when(cakefile)
    target_outputs = target_outputs(cakefile)
    devshell_targets = devshell_targets(cakefile)

    if global_args != [] do
      IO.puts("\nGlobal arguments:")

      for arg <- global_args,
          not hidden_arg(arg.name),
          do: IO.ANSI.format_fragment(["  ", fmt_arg(arg), "\n"]) |> IO.write()
    end

    IO.puts("\nTargets:")

    for %{tgid: tgid, deps_tgids: deps_tgids} = target <- targets do
      target_header = ["  ", :green, tgid, ":", fmt_deps_tgids(deps_tgids), :reset, "\n"]

      case target do
        %Alias{} ->
          ["  ", :green, tgid, ":", fmt_deps_tgids(deps_tgids), "\n", :reset]

        %Local{interpreter: interpreter, env: env} ->
          env =
            for e <- env,
                do: ["    ", fmt_env(e), "\n", :reset]

          when_ =
            for condition <- Map.get(target_when, tgid, []),
                do: [:blue, "    @when ", :faint, condition, "\n", :reset]

          local = [:blue, "    LOCAL ", :faint, interpreter, "\n", :reset]

          [target_header, when_, local, env]

        %Container{} ->
          devshell? = MapSet.member?(devshell_targets, tgid)
          devshell = if devshell?, do: [:blue, "    @devshell\n", :reset], else: ""

          when_ =
            for condition <- Map.get(target_when, tgid, []),
                do: [:blue, "    @when ", :faint, condition, "\n", :reset]

          outputs =
            for output <- Map.get(target_outputs, tgid, []),
                do: [:blue, "    @output ", :faint, output, "\n", :reset]

          args =
            for arg <- Map.get(target_args, tgid, []),
                do: ["    ", fmt_arg(arg), "\n", :reset]

          [target_header, devshell, when_, outputs, args]
      end
      |> IO.ANSI.format()
      |> IO.write()
    end

    :ok
  end

  @spec hidden_arg(String.t()) :: boolean()
  defp hidden_arg(name) do
    String.starts_with?(name, "_") or name in @builtin_docker_args
  end

  @spec target_args(Cakefile.t()) :: %{Type.tgid() => [Arg.t()]}
  defp target_args(%Cakefile{} = cakefile) do
    for %Container{} = target <- cakefile.targets, into: %{} do
      {target.tgid, for(%Arg{} = arg <- target.commands, not hidden_arg(arg.name), do: arg)}
    end
  end

  @spec target_when(Cakefile.t()) :: %{Type.tgid() => [when_condition :: String.t()]}
  defp target_when(%Cakefile{} = cakefile) do
    for %s{} = target when s in [Container, Local] <- cakefile.targets, into: %{} do
      {target.tgid, for(%When{} = when_ <- target.directives, do: when_.condition)}
    end
  end

  @spec target_outputs(Cakefile.t()) :: %{Type.tgid() => [output_path :: String.t()]}
  defp target_outputs(%Cakefile{} = cakefile) do
    for %Container{} = target <- cakefile.targets, into: %{} do
      {target.tgid, for(%Output{} = output <- target.directives, do: output.path)}
    end
  end

  @spec devshell_targets(Cakefile.t()) :: MapSet.t(Type.tgid())
  defp devshell_targets(%Cakefile{} = cakefile) do
    for %Container{} = target <- cakefile.targets,
        Enum.any?(target.directives, &match?(%DevShell{}, &1)),
        into: MapSet.new() do
      target.tgid
    end
  end

  @spec fmt_deps_tgids([String.t()]) :: IO.ANSI.ansidata()
  defp fmt_deps_tgids([]), do: []
  defp fmt_deps_tgids(tgids), do: [" ", :faint, Enum.join(tgids, " ")]

  @spec fmt_arg(Arg.t()) :: IO.ANSI.ansidata()
  defp fmt_arg(%Arg{default_value: nil} = arg), do: [:blue, arg.name]

  defp fmt_arg(%Arg{} = arg),
    do: [:blue, arg.name, :faint, "=#{inspect(arg.default_value)}", :reset]

  @spec fmt_env(Env.t()) :: IO.ANSI.ansidata()
  defp fmt_env(%Env{default_value: nil} = arg), do: [:blue, arg.name]

  defp fmt_env(%Env{} = arg),
    do: [:blue, arg.name, :faint, "=#{inspect(arg.default_value)}", :reset]
end
