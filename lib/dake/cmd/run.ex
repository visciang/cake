defimpl Dake.Cmd, for: Dake.CliArgs.Run do
  @moduledoc """
  run Command.
  """

  alias Dake.CliArgs.Run
  alias Dake.Dag
  alias Dake.Parser.{Dakefile, Docker, Target}
  alias Dake.Pipeline

  @spec exec(Run.t(), Dakefile.t(), Dag.graph()) :: :ok
  def exec(%Run{} = run, %Dakefile{} = dakefile, graph) do
    tgids = ["default" | Dag.tgids(graph)]

    unless run.tgid in tgids do
      Dake.System.halt(:error, "Unknown target '#{run.tgid}'")
    end

    dockerfile = Pipeline.build(dakefile, run.push)

    force_push_build_args = if run.push, do: push_targets_build_args(dakefile), else: []
    build_args = build_args(run.args) ++ force_push_build_args

    {tgid, outdir_opt} = prepare_target_and_output(run)
    tag_opt = if run.tag, do: ["--tag", run.tag], else: []

    System.cmd(
      "docker",
      ["buildx", "build", "--file", dockerfile, "--target", tgid] ++ outdir_opt ++ tag_opt ++ build_args ++ ["."]
    )

    :ok
  end

  @spec prepare_target_and_output(Run.t()) :: {target :: String.t(), output_opts :: [String.t()]}
  defp prepare_target_and_output(%Run{} = run) do
    if run.output do
      output_dir = ".dake_output"
      File.rm_rf!(output_dir)
      File.mkdir_p!(output_dir)
      {"output.#{run.tgid}", ["--output", output_dir]}
    else
      {run.tgid, []}
    end
  end

  @spec push_targets_build_args(Dakefile.t()) :: [String.t()]
  defp push_targets_build_args(%Dakefile{} = dakefile) do
    dakefile.targets
    |> Enum.filter(fn target ->
      match?(%Target.Docker{}, target) and Enum.any?(target.directives, &match?(%Docker.DakePush{}, &1))
    end)
    |> Enum.map(&{String.upcase(&1.tgid), inspect(make_ref())})
    |> build_args()
  end

  @spec build_args([{name :: String.t(), value :: String.t()}]) :: [String.t()]
  defp build_args(args) do
    Enum.flat_map(args, fn {name, value} -> ["--build-arg", "#{name}=#{value}"] end)
  end
end
