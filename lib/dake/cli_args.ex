defmodule Dake.CliArgs do
  @moduledoc """
  CLI argument parser
  """
  defmodule Ls do
    @moduledoc false
    defstruct [:tree]

    @type t :: %__MODULE__{
            tree: nil | boolean()
          }
  end

  defmodule Run do
    @moduledoc false
    defstruct []

    @type t :: %__MODULE__{}
  end

  @type arg :: Ls.t() | Run.t()
  @type result :: {:ok, arg()} | {:error, reason :: String.t()}

  @spec parse([String.t()]) :: result()
  def parse(args) do
    case args do
      ["ls" | args] ->
        {opts, []} = OptionParser.parse!(args, strict: [tree: :boolean])
        {:ok, struct!(Ls, opts)}

      ["run" | args] ->
        {opts, []} = OptionParser.parse!(args, strict: [])
        {:ok, struct!(Run, opts)}

      _ ->
        {:error, "unknow command"}
    end
  rescue
    error in [OptionParser.ParseError] ->
      {:error, Exception.message(error)}
  end
end
