defmodule Cake.Cli do
  alias Cake.{Cmd, Dir, Type}

  defmodule DevShell do
    @enforce_keys [:tgid]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            tgid: nil | Type.tgid()
          }
  end

  defmodule Ls do
    defstruct []

    @type t :: %__MODULE__{}
  end

  defmodule Run do
    @enforce_keys [
      :tgid,
      :args,
      :push,
      :output,
      :tag,
      :timeout,
      :parallelism,
      :progress,
      :save_logs,
      :shell,
      :secrets
    ]
    defstruct @enforce_keys ++ [output_dir: ""]

    @type arg :: {name :: String.t(), value :: String.t()}
    @type t :: %__MODULE__{
            tgid: Type.tgid(),
            args: [arg()],
            push: boolean(),
            output: boolean(),
            output_dir: Path.t(),
            tag: nil | String.t(),
            timeout: timeout(),
            parallelism: pos_integer(),
            progress: Type.progress(),
            save_logs: boolean(),
            shell: boolean(),
            secrets: [String.t()]
          }
  end

  @type result ::
          {:ok, workdir :: Path.t(), cakefile :: Path.t(), Cmd.t()}
          | {:error, reason :: String.t()}
          | {:ignore, reason :: String.t()}

  @version Mix.Project.config()[:version]

  @spec parse([String.t()]) :: result()
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def parse(args) do
    optimus = optimus()

    case Optimus.parse(optimus, args) do
      {:ok, _cli} ->
        {:ignore, Optimus.help(optimus)}

      # coveralls-ignore-start

      {:ok, [:devshell], cli} ->
        {:ok, cli.options.workdir, cli.options.file, %DevShell{tgid: cli.args.target}}

      # coveralls-ignore-stop

      {:ok, [:ls], cli} ->
        {:ok, cli.options.workdir, cli.options.file, %Ls{}}

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
      options: [
        workdir: [
          long: "--workdir",
          help: "Working directory",
          default: ".",
          global: true
        ],
        file: [
          long: "--file",
          help: "Name of the Cakefile",
          default: "Cakefile",
          global: true
        ]
      ],
      subcommands: [
        devshell: [
          name: "devshell",
          about: "Development shell",
          args: [
            target: [
              help: "The devshell target - can be used if multiple devshell targets are available.",
              required: false
            ]
          ]
        ],
        ls: [
          name: "ls",
          about: "List targets"
        ],
        run: [
          name: "run",
          about: "Run the pipeline",
          allow_unknown_args: true,
          args: [
            target: [
              help: "The target of the pipeline (default target: 'all')",
              required: false
            ]
          ],
          flags: [
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
            progress: [
              long: "--progress",
              parser: &parser_progress_option/1,
              default: :interactive,
              help: "Set type of progress output - 'plain' or 'interactive'"
            ],
            tag: [
              long: "--tag",
              help: "Tag the target's container image"
            ],
            secret: [
              long: "--secret",
              multiple: true,
              parser: &parser_secret_option/1,
              help:
                "Secret to expose to the build - ex: '--secret \"id=MY_SECRET,src=./secret\"' (ref. to 'docker build --secret')"
            ],
            timeout: [
              long: "--timeout",
              default: :infinity,
              parser: :integer,
              help: "Pipeline execution timeout (seconds or 'infinity')"
            ],
            parallelism: [
              long: "--parallelism",
              default: System.schedulers_online(),
              parser: :integer,
              help: "Pipeline max parallelism"
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
        timeout =
          if cli.options.timeout == :infinity do
            :infinity
          else
            cli.options.timeout * 1_000
          end

        run = %Run{
          tgid: cli.args.target || "all",
          args: target_args,
          push: cli.flags.push,
          output: cli.flags.output,
          tag: cli.options.tag,
          timeout: timeout,
          parallelism: cli.options.parallelism,
          progress: cli.options.progress,
          save_logs: cli.flags.save_logs,
          shell: cli.flags.shell,
          secrets: cli.options.secret
        }

        {:ok, cli.options.workdir, cli.options.file, run}

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

  @spec parser_progress_option(String.t()) :: Optimus.parser_result()
  defp parser_progress_option(option) do
    options = ["plain", "interactive"]

    if option in options do
      {:ok, String.to_atom(option)}
    else
      {:error, "supported progress value are #{inspect(options)}"}
    end
  end
end
