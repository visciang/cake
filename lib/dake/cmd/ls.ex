defimpl Dake.Cmd, for: Dake.Cli.Ls do
  alias Dake.Cli.Ls
  alias Dake.{Dag, Reporter, Type}
  alias Dake.Parser.Dakefile
  alias Dake.Parser.Container.Arg
  alias Dake.Parser.Target

  @typep target_args :: %{Type.tgid() => [Arg.t()]}

  @spec exec(Ls.t(), Dakefile.t(), Dag.graph()) :: :ok
  def exec(%Ls{}, %Dakefile{} = dakefile, graph) do
    global_args = dakefile.args
    target_args = target_args(dakefile)

    if global_args != [] do
      Reporter.job_notice([], "ls", "\nGlobal arguments:")
      Enum.each(global_args, &Reporter.job_notice([], "ls", " - #{fmt_arg(&1)}"))
    end

    Reporter.job_notice([], "ls", "\nTargets (with arguments):")

    graph
    |> Dag.tgids()
    |> Enum.sort()
    |> Enum.map(&fmt_target(&1, target_args))
    |> Enum.each(&Reporter.job_notice([], "ls", " - #{&1}"))

    :ok
  end

  @spec target_args(Dakefile.t()) :: target_args()
  defp target_args(%Dakefile{} = dakefile) do
    dakefile.targets
    |> Enum.filter(&match?(%Target.Container{}, &1))
    |> Map.new(fn %Target.Container{} = container ->
      {container.tgid, Enum.filter(container.commands, &match?(%Arg{}, &1))}
    end)
  end

  @spec fmt_arg(Arg.t()) :: String.t()
  defp fmt_arg(%Arg{} = arg) do
    if arg.default_value do
      "#{arg.name}=#{inspect(arg.default_value)}"
    else
      arg.name
    end
  end

  @spec fmt_target(Type.tgid(), target_args()) :: IO.chardata()
  defp fmt_target(tgid, target_args) do
    args = Map.get(target_args, tgid, [])
    args = Enum.map_join(args, ", ", &fmt_arg(&1))

    IO.ANSI.format([:green, tgid, :default_color, "  ", args])
  end
end
