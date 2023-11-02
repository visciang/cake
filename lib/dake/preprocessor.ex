defmodule Dake.Preprocessor do
  alias Dake.Parser.Dakefile
  alias Dake.Parser.Directive.{Import, Include, Output}
  alias Dake.Parser.Target.Docker
  alias Dake.Reference

  require Logger

  @type args :: %{(name :: String.t()) => value :: nil | String.t()}
  @type result :: {:ok, Dakefile.t()} | {:error, reason :: String.t()}

  @spec expand(Dakefile.t(), args()) :: result()
  def expand(%Dakefile{} = dakefile, args) do
    Logger.info("dakefile=#{inspect(dakefile.path)}, args=#{inspect(args)}")

    args = Map.merge(Map.new(dakefile.args, &{&1.name, &1.default_value}), args)

    with {:ok, dakefile} <- expand_includes(dakefile) do
      dakefile =
        dakefile
        |> expand_directives_args(args)
        |> normalize_import_paths()

      {:ok, dakefile}
    end
  end

  @spec normalize_import_paths(Dakefile.t()) :: Dakefile.t()
  defp normalize_import_paths(%Dakefile{} = dakefile) do
    update_in(
      dakefile,
      [
        Access.key!(:targets),
        Access.filter(&match?(%Docker{}, &1)),
        Access.key!(:directives),
        Access.filter(&match?(%Import{}, &1)),
        Access.key!(:ref)
      ],
      fn ref ->
        {:ok, ref} = Path.join(Path.dirname(dakefile.path), ref) |> Path.safe_relative()
        ref
      end
    )
  end

  @spec expand_includes(Dakefile.t()) :: result()
  defp expand_includes(%Dakefile{} = dakefile) do
    case rec_expand_included_dakefiles(dakefile) do
      {:ok, included_dakefiles} ->
        includes_args =
          dakefile
          |> get_in([Access.key!(:includes), Access.all(), Access.key!(:args)])
          |> List.flatten()

        included_args = Enum.flat_map(included_dakefiles, & &1.args)
        included_targets = Enum.flat_map(included_dakefiles, & &1.targets)

        dakefile = %Dakefile{
          dakefile
          | includes: [],
            args: dakefile.args ++ included_args ++ includes_args,
            targets: included_targets ++ dakefile.targets
        }

        {:ok, dakefile}

      {:error, _} = error ->
        error
    end
  end

  @spec rec_expand_included_dakefiles(Dakefile.t()) :: {:ok, [Dakefile.t()]} | {:error, reason :: String.t()}
  defp rec_expand_included_dakefiles(%Dakefile{} = dakefile) do
    Enum.reduce_while(dakefile.includes, {:ok, []}, fn %Include{} = include, {:ok, included_dakefiles} ->
      with {:ok, included_dakefile_path} <- Reference.get_include(dakefile, include),
           Logger.info("dakefile=#{inspect(included_dakefile_path)}"),
           {:ok, included_dakefile} <- Dake.load_and_parse_dakefile(included_dakefile_path),
           included_dakefile = track_included_from(included_dakefile, included_dakefile_path),
           {:ok, dakefile} <- expand(included_dakefile, %{}) do
        {:cont, {:ok, included_dakefiles ++ [dakefile]}}
      else
        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  @spec expand_directives_args(Dakefile.t(), args()) :: Dakefile.t()
  defp expand_directives_args(%Dakefile{} = dakefile, args) do
    update_in(
      dakefile,
      [
        Access.key!(:targets),
        Access.filter(&match?(%Docker{}, &1)),
        Access.key!(:directives),
        Access.all()
      ],
      fn
        %Output{} = output -> %Output{output | dir: expand_vars(output.dir, args)}
        other_directive -> other_directive
      end
    )
  end

  @spec expand_vars(String.t(), args()) :: String.t()
  defp expand_vars(string, bindings) do
    string =
      Regex.replace(~r/\$(\w+)/, string, fn full_match, variable ->
        Map.get(bindings, variable) || full_match
      end)

    Regex.replace(~r/\$\{(\w+)(?::-(.*))?\}/, string, fn full_match, variable, default ->
      Map.get(bindings, variable, default) || full_match
    end)
  end

  @spec track_included_from(Dakefile.t(), Path.t()) :: Dakefile.t()
  defp track_included_from(%Dakefile{} = dakefile, dakefile_path) do
    put_in(
      dakefile,
      [
        Access.key!(:targets),
        Access.filter(&match?(%Docker{}, &1)),
        Access.key!(:included_from_ref)
      ],
      dakefile_path
    )
  end
end
