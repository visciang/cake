defmodule Dake.Preprocessor do
  @moduledoc """
  Preprocessor.
  """

  alias Dake.Parser.Dakefile
  alias Dake.Parser.Docker.{DakeImage, DakeOutput}
  alias Dake.Parser.Target.Docker

  @type args :: %{(name :: String.t()) => value :: nil | String.t()}
  @type result :: {:ok, Dakefile.t()} | {:error, reason :: term()}

  @spec expand(Dakefile.t(), args()) :: result()
  def expand(%Dakefile{} = dakefile, args) do
    with {:ok, dakefile} <- expand_includes(dakefile),
         {:ok, dakefile} <- expand_directives_args(dakefile, args) do
      {:ok, dakefile}
    end
  end

  @spec expand_includes(Dakefile.t()) :: result()
  defp expand_includes(%Dakefile{} = dakefile) do
    dakefile.includes
    |> Enum.each(fn %Dakefile.Include{} = include ->
      IO.puts("!!!! TODO #{inspect(include)} !!!!")
    end)

    {:ok, dakefile}
  end

  @spec expand_directives_args(Dakefile.t(), args()) :: result()
  defp expand_directives_args(%Dakefile{} = dakefile, args) do
    dakefile =
      update_in(
        dakefile,
        [Access.key!(:targets), Access.filter(&match?(%Docker{}, &1)), Access.key!(:directives), Access.all()],
        fn
          %DakeImage{} = image -> %DakeImage{image | name: do_expansion(image.name, args)}
          %DakeOutput{} = output -> %DakeOutput{output | dir: do_expansion(output.dir, args)}
          other_directive -> other_directive
        end
      )

    {:ok, dakefile}
  end

  @spec do_expansion(String.t(), args()) :: String.t()
  defp do_expansion(string, bindings) do
    string =
      Regex.replace(~r/\$(\w+)/, string, fn full_match, variable ->
        Map.get(bindings, variable) || full_match
      end)

    Regex.replace(~r/\$\{(\w+)(?::-(.*))?\}/, string, fn full_match, variable, default ->
      Map.get(bindings, variable, default) || full_match
    end)
  end
end
