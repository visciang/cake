defmodule Cake.Preprocessor do
  alias Cake.Parser.{Cakefile, Target}
  alias Cake.Parser.Directive.{Include, Output}
  alias Cake.Reference

  require Logger

  @type args :: %{(name :: String.t()) => value :: nil | String.t()}
  @type result :: {:ok, Cakefile.t()} | {:error, reason :: String.t()}

  @spec expand(Cakefile.t(), args()) :: result()
  def expand(%Cakefile{} = cakefile, args) do
    Logger.info("cakefile=#{inspect(cakefile.path)}, args=#{inspect(args)}")

    args = Map.merge(Map.new(cakefile.args, &{&1.name, &1.default_value}), args)

    with {:ok, cakefile} <- expand_includes(cakefile) do
      cakefile = expand_directives_args(cakefile, args)

      {:ok, cakefile}
    end
  end

  @spec expand_includes(Cakefile.t()) :: result()
  defp expand_includes(%Cakefile{} = cakefile) do
    includes_args = Enum.flat_map(cakefile.includes, & &1.args)

    case rec_expand_included_cakefiles(cakefile) do
      {:ok, included_cakefiles} ->
        included_args = Enum.flat_map(included_cakefiles, & &1.args)
        included_targets = Enum.flat_map(included_cakefiles, & &1.targets)

        expanded_cakefile = %Cakefile{
          cakefile
          | includes: [],
            args: cakefile.args ++ included_args ++ includes_args,
            targets: included_targets ++ cakefile.targets
        }

        {:ok, expanded_cakefile}

      {:error, _} = error ->
        error
    end
  end

  @spec rec_expand_included_cakefiles(Cakefile.t()) :: {:ok, [Cakefile.t()]} | {:error, reason :: String.t()}
  defp rec_expand_included_cakefiles(%Cakefile{} = cakefile) do
    Enum.reduce_while(cakefile.includes, {:ok, []}, fn
      %Include{} = include, {:ok, included_cakefiles} ->
        with {:ok, included_path} <- Reference.get_include(include),
             included_cakefile_path = Path.join(included_path, "Cakefile"),
             true <- File.exists?(included_cakefile_path),
             Logger.info("cakefile=#{inspect(included_cakefile_path)}"),
             {:ok, included_cakefile} <- Cake.load_and_parse_cakefile(included_cakefile_path),
             included_cakefile = track_included_from(included_cakefile, included_cakefile_path),
             {:ok, cakefile} <- expand(included_cakefile, %{}) do
          {:cont, {:ok, included_cakefiles ++ [cakefile]}}
        else
          false ->
            {:halt, {:error, "Cannot find Cakefile in include from #{include.ref}"}}

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
