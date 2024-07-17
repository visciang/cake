defprotocol Cake.Parser.Target.Container.Fmt do
  @spec fmt(t()) :: String.t()
  def fmt(data)
end

defmodule Cake.Parser.Target.Container do
  # target:
  #     @output output/
  #     FROM image
  #     ARG X=1
  #     RUN ...

  alias Cake.Parser.Target.Container.{Arg, Command, From}
  alias Cake.Parser.Directive.{Output, Push}
  alias Cake.Type

  @enforce_keys [:tgid]
  defstruct @enforce_keys ++ [included_from_ref: nil, directives: [], commands: []]

  @type directive :: Output.t() | Push.t()
  @type command :: Arg.t() | From.t() | Command.t()

  @type t :: %__MODULE__{
          tgid: Type.tgid(),
          directives: [directive()],
          commands: [command()],
          included_from_ref: nil | Path.t()
        }

  defmodule From do
    # Container `FROM <image> [AS <as>]`

    @enforce_keys [:image]
    defstruct @enforce_keys ++ [:as]

    @type t :: %__MODULE__{
            image: String.t(),
            as: nil | String.t()
          }
  end

  defmodule Arg do
    # Container `ARG <name>[=<default_value>]`

    @enforce_keys [:name]
    defstruct @enforce_keys ++ [:default_value]

    @type t :: %__MODULE__{
            name: String.t(),
            default_value: nil | String.t()
          }
  end

  defmodule Command do
    # Generic Container command `INSTRUCTION [--option=value]* arguments`

    defmodule Option do
      # Generic Container option

      @enforce_keys [:name, :value]
      defstruct @enforce_keys

      @type t :: %__MODULE__{
              name: String.t(),
              value: String.t()
            }
    end

    @enforce_keys [:instruction, :arguments]
    defstruct @enforce_keys ++ [options: []]

    @type t :: %__MODULE__{
            instruction: String.t(),
            options: [Option.t(), ...],
            arguments: String.t()
          }
  end

  defimpl Cake.Parser.Target.Container.Fmt, for: From do
    @spec fmt(From.t()) :: String.t()
    def fmt(%From{} = from) do
      if from.as do
        # coveralls-ignore-start
        "FROM #{from.image} AS #{from.as}"
        # coveralls-ignore-stop
      else
        "FROM #{from.image}"
      end
    end
  end

  defimpl Cake.Parser.Target.Container.Fmt, for: Arg do
    @spec fmt(Arg.t()) :: String.t()
    def fmt(%Arg{} = arg) do
      if arg.default_value do
        "ARG #{arg.name}=#{inspect(arg.default_value)}"
      else
        "ARG #{arg.name}"
      end
    end
  end

  defimpl Cake.Parser.Target.Container.Fmt, for: Command do
    @spec fmt(Command.t()) :: String.t()
    def fmt(%Command{} = command) do
      options = Enum.map_join(command.options, " ", &"--#{&1.name}=#{&1.value}")
      "#{command.instruction} #{options} #{command.arguments}"
    end
  end
end
