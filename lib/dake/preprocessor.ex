defmodule Dake.Preprocessor do
  @moduledoc """
  Preprocessor.

  - expand dake @directives arguments
  - (recursivelly) expand the included Dakefiles:
    - included targets and arguments are merged with the main Dakefile
    - the included ctx is copied locally under the .dake/ directory
  """

  alias Dake.Parser.Dakefile
  alias Dake.Parser.Docker.DakeOutput
  alias Dake.Parser.Target.Docker

  @type args :: %{(name :: String.t()) => value :: nil | String.t()}

  @spec expand(Dakefile.t(), args()) :: Dakefile.t()
  def expand(%Dakefile{} = dakefile, args) do
    args = Map.merge(Map.new(dakefile.args, &{&1.name, &1.default_value}), args)

    includes = dakefile.includes

    dakefile =
      dakefile
      |> expand_includes()
      |> expand_directives_args(args)

    copy_include_ctx(includes)

    dakefile
  end

  @spec expand_includes(Dakefile.t()) :: Dakefile.t()
  defp expand_includes(%Dakefile{} = dakefile) do
    includes_args =
      dakefile
      |> get_in([Access.key!(:includes), Access.all(), Access.key!(:args)])
      |> List.flatten()

    included_dakefiles =
      Enum.map(dakefile.includes, fn %Dakefile.Include{} = include ->
        included_dakefile = Dake.load_and_parse_dakefile(include.ref)
        expand(included_dakefile, %{})
      end)

    included_args = Enum.flat_map(included_dakefiles, & &1.args)
    included_targets = Enum.flat_map(included_dakefiles, & &1.targets)

    %Dakefile{
      dakefile
      | includes: [],
        args: dakefile.args ++ included_args ++ includes_args,
        targets: included_targets ++ dakefile.targets
    }
  end

  @spec copy_include_ctx([Dakefile.Include.t()]) :: :ok
  defp copy_include_ctx(includes) do
    Enum.each(includes, fn %Dakefile.Include{} = include ->
      include_ctx_dir = Path.join(Path.dirname(include.ref), ".dake")

      if File.exists?(include_ctx_dir) do
        File.cp_r!(include_ctx_dir, ".dake")
      end
    end)
  end

  @spec expand_directives_args(Dakefile.t(), args()) :: Dakefile.t()
  defp expand_directives_args(%Dakefile{} = dakefile, args) do
    update_in(
      dakefile,
      [Access.key!(:targets), Access.filter(&match?(%Docker{}, &1)), Access.key!(:directives), Access.all()],
      fn
        %DakeOutput{} = output -> %DakeOutput{output | dir: expand_vars(output.dir, args)}
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
end
