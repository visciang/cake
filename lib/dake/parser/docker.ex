defmodule Dake.Parser.Docker do
  defmodule DakeInclude do
    @moduledoc """
    Docker `DAKE_INCLUDE <target>`.
    """

    alias Dake.Type

    @enforce_keys [:tgid]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            tgid: Type.tgid()
          }
  end

  defmodule DakeOutput do
    @moduledoc """
    `@output <dir>`.
    """

    @enforce_keys [:dir]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            dir: Path.t()
          }
  end

  defmodule DakePush do
    @moduledoc """
    `@push`.
    """

    defstruct []

    @type t :: %__MODULE__{}
  end

  defmodule From do
    @moduledoc """
    Docker `FROM <image> [AS <as>]`.
    """

    @enforce_keys [:image]
    defstruct @enforce_keys ++ [:as]

    @type t :: %__MODULE__{
            image: String.t(),
            as: nil | String.t()
          }
  end

  defmodule Arg do
    @moduledoc """
    Docker `ARG <name>[=<default_value>]`.
    """

    @enforce_keys [:name]
    defstruct @enforce_keys ++ [:default_value]

    @type t :: %__MODULE__{
            name: String.t(),
            default_value: nil | String.t()
          }
  end

  defmodule Command do
    @moduledoc """
    Generic Docker command `INSTRUCTION [--option=value]* arguments`.
    """

    defmodule Option do
      @moduledoc """
      Generic Docker option.
      """

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

    @spec find_option([Option.t()], String.t()) :: nil | Option.t()
    def find_option(nil, _name), do: nil

    def find_option(options, name) do
      Enum.find(options, &match?(%Option{name: ^name}, &1))
    end
  end
end
