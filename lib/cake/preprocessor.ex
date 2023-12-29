defmodule Cake.Preprocessor do
  alias Cake.Parser.{Cakefile, Target}
  alias Cake.Parser.Directive.{Import, Include, Output}
  alias Cake.Reference

  require Logger

  @type args :: %{(name :: String.t()) => value :: nil | String.t()}
  @type result :: {:ok, Cakefile.t()} | {:error, reason :: String.t()}

  @spec expand(Cakefile.t(), args()) :: result()
  def expand(%Cakefile{} = cakefile, args) do
    Logger.info("cakefile=#{inspect(cakefile.path)}, args=#{inspect(args)}")

    args = Map.merge(Map.new(cakefile.args, &{&1.name, &1.default_value}), args)

    with {:ok, cakefile} <- expand_includes(cakefile) do
      cakefile =
        cakefile
        |> expand_directives_args(args)
        |> normalize_import_paths()

      {:ok, cakefile}
    end
  end

  @spec normalize_import_paths(Cakefile.t()) :: Cakefile.t()
  defp normalize_import_paths(%Cakefile{} = cakefile) do
    update_in(
      cakefile,
      [
        Access.key!(:targets),
        Access.filter(&match?(%Target{}, &1)),
        Access.key!(:directives),
        Access.filter(&match?(%Import{}, &1)),
        Access.key!(:ref)
      ],
      fn ref ->
        {:ok, ref} = Path.join(Path.dirname(cakefile.path), ref) |> Path.safe_relative()
        ref
      end
    )
  end

  @spec expand_includes(Cakefile.t()) :: result()
  defp expand_includes(%Cakefile{} = cakefile) do
    case rec_expand_included_cakefiles(cakefile) do
      {:ok, included_cakefiles} ->
        includes_args =
          cakefile
          |> get_in([Access.key!(:includes), Access.all(), Access.key!(:args)])
          |> List.flatten()

        included_args = Enum.flat_map(included_cakefiles, & &1.args)
        included_targets = Enum.flat_map(included_cakefiles, & &1.targets)

        cakefile = %Cakefile{
          cakefile
          | includes: [],
            args: cakefile.args ++ included_args ++ includes_args,
            targets: included_targets ++ cakefile.targets
        }

        {:ok, cakefile}

      {:error, _} = error ->
        error
    end
  end

  @spec rec_expand_included_cakefiles(Cakefile.t()) :: {:ok, [Cakefile.t()]} | {:error, reason :: String.t()}
  defp rec_expand_included_cakefiles(%Cakefile{} = cakefile) do
    Enum.reduce_while(cakefile.includes, {:ok, []}, fn
      %Include{} = include, {:ok, included_cakefiles} ->
        with {:ok, included_cakefile_path} <- Reference.get_include(cakefile, include),
             Logger.info("cakefile=#{inspect(included_cakefile_path)}"),
             {:ok, included_cakefile} <- Cake.load_and_parse_cakefile(included_cakefile_path),
             included_cakefile = track_included_from(included_cakefile, included_cakefile_path),
             {:ok, cakefile} <- expand(included_cakefile, %{}) do
          {:cont, {:ok, included_cakefiles ++ [cakefile]}}
        else
          {:error, _} = error ->
            {:halt, error}
        end
    end)
  end

  @spec expand_directives_args(Cakefile.t(), args()) :: Cakefile.t()
  defp expand_directives_args(%Cakefile{} = cakefile, args) do
    update_in(
      cakefile,
      [
        Access.key!(:targets),
        Access.filter(&match?(%Target{}, &1)),
        Access.key!(:directives),
        Access.all()
      ],
      fn
        %Output{} = output -> %Output{output | path: expand_vars(output.path, args)}
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

  @spec track_included_from(Cakefile.t(), Path.t()) :: Cakefile.t()
  defp track_included_from(%Cakefile{} = cakefile, cakefile_path) do
    put_in(
      cakefile,
      [
        Access.key!(:targets),
        Access.filter(&match?(%Target{}, &1)),
        Access.key!(:included_from_ref)
      ],
      cakefile_path
    )
  end
end
