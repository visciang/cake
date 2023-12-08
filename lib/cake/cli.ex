defmodule Cake.Cli do
  alias Cake.{Cmd, Dir, Type}

  defmodule Ls do
    defstruct []

    @type t :: %__MODULE__{}
  end

  defmodule Run do
    @enforce_keys [
      :ns,
      :tgid,
      :args,
      :push,
      :output,
      :tag,
      :timeout,
      :parallelism,
      :verbose,
      :save_logs,
      :shell,
      :secrets
    ]
    defstruct @enforce_keys ++ [output_dir: ""]

    @type arg :: {name :: String.t(), value :: String.t()}
    @type t :: %__MODULE__{
            ns: [Type.tgid()],
            tgid: Type.tgid(),
            args: [arg()],
            push: boolean(),
            output: boolean(),
            output_dir: Path.t(),
            tag: nil | String.t(),
            timeout: timeout(),
            parallelism: pos_integer(),
            verbose: boolean(),
            save_logs: boolean(),
            shell: boolean(),
            secrets: [String.t()]
          }
  end

  @type result :: {:ok, Cmd.t()} | {:error, reason :: String.t()}

  @version Mix.Project.config()[:version]

  @spec parse([String.t()]) :: result()
  def parse(args) do
    optimus = optimus()

    case Optimus.parse(optimus, args) do
      {:ok, _cli} ->
        {:ignore, Optimus.help(optimus)}

      {:ok, [:ls], _cli} ->
        {:ok, %Ls{}}

      {:ok, [:run], cli} ->
        parse_run(cli)

      {:error, _} = error ->
        error

      {:error, _subcommand_path, err} ->
        {:error, err}

      :version ->
        Cake.System.halt(:ok, Optimus.Title.title(optimus) |> IO.iodata_to_binary())

      :help ->
        {:ignore, Optimus.help(optimus)}

      {:help, subcommand_path} ->
        {optimus_subcommand, _} = Optimus.fetch_subcommand(optimus, subcommand_path)
        {:ignore, Optimus.help(optimus_subcommand)}
    end
  end

  @spec optimus :: Optimus.t()
  defp optimus do
    Optimus.new!(
      name: "cake",
      description: "cake (Container-mAKE pipeline)",
      version: @version,
      subcommands: [
        run: [
          name: "run",
          about: "Run the pipeline",
          allow_unknown_args: true,
          args: [
            target: [
              value_name: "TARGET",
              help: "The target of the pipeline"
            ]
          ],
          flags: [
            verbose: [
              long: "--verbose",
              help: "Show jobs log to the console"
            ],
            save_logs: [
              long: "--save-logs",
              help: "Save logs under #{Dir.log()} directory"
            ],
            push: [
              long: "--push",
              help: "Includes push targets (ref. @push directive) in the pipeline run"
            ],
            output: [
              long: "--output",
              help: "Output the target artifacts (ref. @output directive) under #{Dir.output()} directory"
            ],
            shell: [
              long: "--shell",
              help: "Open an interactive shell in the target"
            ]
          ],
          options: [
            tag: [
              long: "--tag",
              value_name: "TAG",
              help: "Tag the target's container image"
            ],
            secret: [
              long: "--secret",
              value_name: "SECRET",
              multiple: true,
              parser: &parser_secret_option/1,
              help: "Secret to expose to the build (ref. to 'docker build --secret')"
            ],
            timeout: [
              long: "--timeout",
              value_name: "TIMEOUT",
              default: :infinity,
              parser: :integer,
              help: "Pipeline execution timeout (seconds)"
            ],
            parallelism: [
              long: "--parallelism",
              value_name: "PARALLELISM",
              default: System.schedulers_online(),
              parser: :integer,
              help: "Pipeline max parallelism"
            ]
          ]
        ],
        ls: [
          name: "ls",
          about: "List targets"
        ]
      ]
    )
  end

  @spec parse_target_args(Optimus.ParseResult.t()) :: result()
  defp parse_run(cli) do
    case parse_target_args(cli.unknown) do
      {:ok, target_args} ->
        timeout =
          if cli.options.timeout == :infinity do
            :infinity
          else
            cli.options.timeout * 1_000
          end

        run = %Run{
          ns: [],
          tgid: cli.args.target,
          args: target_args,
          push: cli.flags.push,
          output: cli.flags.output,
          tag: cli.options.tag,
          timeout: timeout,
          parallelism: cli.options.parallelism,
          verbose: cli.flags.verbose,
          save_logs: cli.flags.save_logs,
          shell: cli.flags.shell,
          secrets: cli.options.secret
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

  @spec parser_secret_option(String.t()) :: Optimus.parser_result()
  defp parser_secret_option(option) do
    re = ~S"id=\w+(,(src|source)=.+)?"

    if option =~ ~r/^#{re}$/ do
      {:ok, option}
    else
      {:error, "supported format is '#{re}'"}
    end
  end
end
