defimpl Cake.Cmd, for: Cake.Cli.DevShell do
  alias Cake.{Cmd, Dag, Type}
  alias Cake.Cli.{DevShell, Run}
  alias Cake.Parser.Cakefile
  alias Cake.Parser.Target
  alias Cake.Parser.Directive

  @spec exec(DevShell.t(), Cakefile.t(), Dag.graph()) :: :ok
  def exec(%DevShell{} = devshell, %Cakefile{} = cakefile, graph) do
    case default_target(devshell.tgid, cakefile) do
      {:ok, tgid} ->
        run_cmd = %Run{
          on_import?: false,
          ns: [],
          tgid: tgid,
          args: [],
          push: false,
          output: false,
          tag: nil,
          timeout: :infinity,
          parallelism: System.schedulers_online(),
          progress: :interactive,
          save_logs: false,
          shell: true,
          secrets: []
        }

        Cmd.exec(run_cmd, cakefile, graph)

      {:error, reason} ->
        Cake.System.halt(:error, reason)
    end

    :ok
  end

  @spec default_target(nil | Type.tgid(), Cakefile.t()) :: {:ok, Type.tgid()} | {:error, String.t()}
  defp default_target(nil, %Cakefile{} = cakefile) do
    devshell_tgids = devshell_targets(cakefile)

    case Enum.to_list(devshell_tgids) do
      [] ->
        {:error, "No devshell targets available"}

      [target] ->
        {:ok, target}

      [_ | _] ->
        {:error, "Multiple devshell: please select one of '#{Enum.join(devshell_tgids, " ")}'"}
    end
  end

  defp default_target(tgid, %Cakefile{} = cakefile) do
    devshell_tgids = devshell_targets(cakefile)

    if MapSet.member?(devshell_tgids, tgid) do
      {:ok, tgid}
    else
      {:error, "Bad target, please select one of '#{Enum.join(devshell_tgids, " ")}'"}
    end
  end

  @spec devshell_targets(Cakefile.t()) :: MapSet.t(Type.tgid())
  defp devshell_targets(%Cakefile{} = cakefile) do
    for %Target{} = target <- cakefile.targets,
        Enum.any?(target.directives, &match?(%Directive.DevShell{}, &1)),
        into: MapSet.new() do
      target.tgid
    end
  end
end
