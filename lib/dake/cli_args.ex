defmodule Dake.CliArgs do
  alias Dake.{Cmd, Type}

  defmodule Ls do
    defstruct [:tree]

    @type t :: %__MODULE__{
            tree: nil | boolean()
          }
  end

  defmodule Run do
    @enforce_keys [:tgid, :args, :push, :output, :tag]
    defstruct @enforce_keys

    @type arg :: {name :: String.t(), value :: String.t()}
    @type t :: %__MODULE__{
            tgid: nil | Type.tgid(),
            args: [arg()],
            push: boolean(),
            output: boolean(),
            tag: nil | String.t()
          }
  end

  @type result :: {:ok, Cmd.t()} | {:error, reason :: String.t()}

  @version Mix.Project.config()[:version]

  @spec parse([String.t()]) :: result()
  def parse(args) do
    optimus = optimus()

    case Optimus.parse(optimus, args) do
      {:ok, _cli} ->
        {:error, Optimus.help(optimus)}

      {:ok, [:ls], cli} ->
        {:ok, %Ls{tree: cli.flags.tree}}

      {:ok, [:run], cli} ->
        parse_run(cli)

      {:error, _} = error ->
        error

      {:error, _subcommand_path, err} ->
        {:error, err}

      :version ->
        Dake.System.halt(:ok, Optimus.Title.title(optimus))

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
      description: "dake (Docker-mAKE pipeline)",
      version: @version,
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
              help: "Includes push targets (ref. @push directive) in the pipeline run"
            ],
            output: [
              short: "-o",
              long: "--output",
              help: "Output the target artifacts (ref. @output directive) under ./.dake_ouput directory"
            ]
          ],
          options: [
            tag: [
              short: "-t",
              long: "--tag",
              value_name: "TAG",
              help: "Tag the target's docker image"
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
        run = %Run{
          tgid: cli.args.target,
          args: target_args,
          push: cli.flags.push,
          output: cli.flags.output,
          tag: cli.options.tag
        }

        {:ok, run}

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
