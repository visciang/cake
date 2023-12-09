defimpl Cake.Cmd, for: Cake.Cli.Ls do
  alias Cake.Cli.Ls
  alias Cake.{Dag, Dir, Reporter, Type}
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
      Reporter.job_notice([], "ls", "\nGlobal arguments:")
      Enum.each(global_args, &Reporter.job_notice([], "ls", " - #{fmt_arg(&1)}"))
    end

    Reporter.job_notice([], "ls", "\nTargets:")

    graph
    |> Dag.tgids()
    |> Enum.sort()
    |> Enum.map(&fmt_target(&1, target_args))
    |> Enum.each(&Reporter.job_notice([], "ls", " - #{&1}"))

    :ok
  end

  @spec target_args(Cakefile.t()) :: target_args()
  defp target_args(%Cakefile{} = cakefile) do
    cakefile.targets
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
