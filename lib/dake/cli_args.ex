defmodule Dake.CliArgs do
  @moduledoc """
  CLI argument parser
  """

  alias Dake.Type

  defmodule Ls do
    @moduledoc false
    defstruct [:tree]

    @type t :: %__MODULE__{
            tree: nil | boolean()
          }
  end

  defmodule Run do
    @moduledoc false
    @enforce_keys [:tgid, :args, :push, :output]
    defstruct @enforce_keys

    @type arg :: {name :: String.t(), value :: String.t()}
    @type t :: %__MODULE__{
            tgid: Type.tgid(),
            args: [arg()],
            push: boolean(),
            output: boolean()
          }
  end

  @type arg :: Ls.t() | Run.t()
  @type result :: {:ok, arg()} | {:error, reason :: String.t()}

  @version Mix.Project.config()[:version]

  @spec parse([String.t()]) :: result()
  def parse(args) do
    optimus = optimus()

    case Optimus.parse(optimus, args) do
      {:ok, [:ls], cli} ->
        {:ok, %Ls{tree: cli.flags.tree}}

      {:ok, [:run], cli} ->
        parse_run(cli)

      {:error, _} = error ->
        error

      :version ->
        IO.puts("dake v#{@version}")
        System.halt()

      :help ->
        {:error, Optimus.help(optimus)}

      {:help, subcommand_path} ->
        {optimus_subcommand, _} = Optimus.fetch_subcommand(optimus, subcommand_path)
        {:error, Optimus.help(optimus_subcommand)}
    end
  end

  @spec optimus :: Optimus.t()
  defp optimus do
    Optimus.new!(
      name: "dake",
      description: "Docker-Make pipeline",
      subcommands: [
        run: [
          name: "run",
          about: "Run the pipeline",
          allow_unknown_args: true,
          args: [
            target: [
              value_name: "TARGET",
              help: "The target of the pipeline. If not specified all targets are executed",
              required: false
            ]
          ],
          flags: [
            push: [
              short: "-p",
              long: "--push",
              help: "Includes push targets (ref. DAKE_PUSH) in the pipeline run"
            ],
            output: [
              short: "-o",
              long: "--output",
              help: "Output the target artifacts (ref. DAKE_SAVE_OUTPUT) under ./.dake_ouput directory"
            ]
          ]
        ],
        ls: [
          name: "ls",
          about: "List targets",
          flags: [
            tree: [
              short: "-t",
              long: "--tree",
              help: "Show the pipeline originating from each target"
            ]
          ]
        ]
      ]
    )
  end

  @spec parse_target_args(Optimus.ParseResult.t()) :: result()
  defp parse_run(cli) do
    case parse_target_args(cli.unknown) do
      {:ok, target_args} ->
        tgid = cli.args.target || "default"
        {:ok, %Run{tgid: tgid, args: target_args, push: cli.flags.push, output: cli.flags.output}}

      {:error, _} = error ->
        error
    end
  end

  @spec parse_target_args([String.t()]) ::
          {:ok, [{name :: String.t(), value :: String.t()}]} | {:error, reason :: String.t()}
  defp parse_target_args(args) do
    Enum.reduce_while(args, {:ok, []}, fn arg, {:ok, acc} ->
      case String.split(arg, "=", parts: 2) do
        [name, value] ->
          {:cont, {:ok, acc ++ [{name, value}]}}

        [bad_arg] ->
          {:halt, {:error, "bad target argument: #{bad_arg}"}}
      end
    end)
  end
end
