defmodule Cake.Preprocessor do
  alias Cake.Parser.Cakefile
  alias Cake.Parser.Directive.{Include, Output, When}
  alias Cake.Parser.Target.{Container, Local}
  alias Cake.Parser.Target.Container.{Arg, Command, Env, From}
  alias Cake.{Reference, Type}

  require Logger

  @type args :: %{(name :: String.t()) => value :: nil | String.t()}
  @type result :: {:ok, Cakefile.t()} | {:error, reason :: String.t()}
  @type namespace :: [String.t()]

  @typep arg_names() :: MapSet.t(String.t())
  @typep target_arg_names() :: %{Type.tgid() => arg_names()}

  @spec expand(Cakefile.t(), args(), namespace(), base_path :: Path.t()) :: result()
  def expand(%Cakefile{} = cakefile, args, namespace \\ [], base_path \\ ".") do
    Logger.info("""
    cakefile=#{inspect(cakefile.path)} \
    args=#{inspect(args)} \
    namespace=#{inspect(namespace)} \
    base_path=#{inspect(base_path)}
    """)

    with {:ok, included_cakefiles} <- expand_included_cakefiles(cakefile, namespace, base_path) do
      included_args = Enum.flat_map(included_cakefiles, & &1.args)
      included_targets = Enum.flat_map(included_cakefiles, & &1.targets)

      cakefile = %Cakefile{
        path: cakefile.path,
        includes: [],
        args: (cakefile.args ++ included_args) |> args_list_to_map() |> args_map_to_list(),
        targets: included_targets ++ cakefile.targets
      }

      args = cakefile.args |> args_list_to_map() |> Map.merge(args)
      cakefile = set_args(cakefile, args)

      {:ok, cakefile}
    end
  end

  @spec expand_included_cakefiles(Cakefile.t(), namespace(), base_path :: Path.t()) ::
          {:ok, [Cakefile.t()]} | {:error, reason :: String.t()}
  defp expand_included_cakefiles(%Cakefile{} = cakefile, namespace, base_path) do
    Enum.reduce_while(cakefile.includes, {:ok, []}, fn
      %Include{} = include, {:ok, included_cakefiles} ->
        with {:ok, included_cakefile_path} <- get_include(include, base_path),
             {:ok, included_cakefile} <- Cake.parse_cakefile(included_cakefile_path),
             included_cakefile = track_included_from(included_cakefile, included_cakefile_path),
             namespace = namespace ++ [include.namespace],
             included_cakefile = apply_namespace(included_cakefile, namespace),
             included_cakefile_args = args_list_to_map(include.args),
             base_path = Path.dirname(included_cakefile_path),
             {:ok, cakefile} <- expand(included_cakefile, included_cakefile_args, namespace, base_path) do
          {:cont, {:ok, included_cakefiles ++ [cakefile]}}
        else
          {:error, _} = error ->
            {:halt, error}
        end
    end)
  end

  @spec get_include(Include.t(), base_path :: Path.t()) ::
          {:ok, included_cakefile_path :: Path.t()} | {:error, reason :: String.t()}
  defp get_include(%Include{} = include, base_path) do
    with {:ok, included_path} <- Reference.get_include(include, base_path),
         included_cakefile_path = Path.join(included_path, "Cakefile"),
         true <- File.exists?(included_cakefile_path) do
      Logger.info("cakefile=#{inspect(included_cakefile_path)}")
      {:ok, included_cakefile_path}
    else
      {:error, _} = error ->
        error

      false ->
        {:error, "Cannot find Cakefile in include from #{include.ref}"}
    end
  end

  @spec set_args(Cakefile.t(), args()) :: Cakefile.t()
  defp set_args(%Cakefile{} = cakefile, args) do
    output_path = [
      Access.key!(:targets),
      Access.filter(&match?(%Container{}, &1)),
      Access.key!(:directives),
      Access.filter(&match?(%Output{}, &1)),
      Access.key!(:path)
    ]

    cakefile = update_in(cakefile, output_path, fn path -> expand_vars(path, args) end)

    args_paths = [
      [
        Access.key!(:args),
        Access.filter(&Map.has_key?(args, &1.name))
      ],
      [
        Access.key!(:targets),
        Access.filter(&match?(%Container{}, &1)),
        Access.key!(:commands),
        Access.filter(&(match?(%Arg{}, &1) and Map.has_key?(args, &1.name)))
      ]
    ]

    cakefile =
      for path <- args_paths, reduce: cakefile do
        %Cakefile{} = cakefile ->
          update_in(cakefile, path, fn %Arg{} = arg ->
            %Arg{arg | default_value: Map.fetch!(args, arg.name)}
          end)
      end

    cakefile
  end

  @spec expand_vars(String.t(), args()) :: String.t()
  defp expand_vars(string, bindings) do
    replace_vars(string, fn full_match, variable, default ->
      Map.get(bindings, variable, default) || full_match
    end)
  end

  @spec track_included_from(Cakefile.t(), Path.t()) :: Cakefile.t()
  defp track_included_from(%Cakefile{} = cakefile, cakefile_path) do
    put_in(
      cakefile,
      [
        Access.key!(:targets),
        Access.filter(&(match?(%Container{}, &1) or match?(%Local{}, &1))),
        Access.key!(:__included_from_ref)
      ],
      cakefile_path
    )
  end

  @spec apply_namespace(Cakefile.t(), namespace()) :: Cakefile.t()
  defp apply_namespace(%Cakefile{} = cakefile, namespace) do
    cakefile
    |> apply_namespace_to_variable_names(namespace)
    |> apply_namespace_to_variable_references(namespace)
    |> apply_namespace_to_target_names(namespace)
    |> apply_namespace_to_target_references(namespace)
    |> apply_namespace_to_include_args(namespace)
  end

  @spec apply_namespace_to_variable_names(Cakefile.t(), namespace()) :: Cakefile.t()
  defp apply_namespace_to_variable_names(%Cakefile{} = cakefile, namespace) do
    upcase_namespace = for n <- namespace, do: String.upcase(n)

    paths = [
      [
        Access.key!(:args),
        Access.all(),
        Access.key!(:name)
      ],
      [
        Access.key!(:targets),
        Access.filter(&match?(%Local{}, &1)),
        Access.key!(:env),
        Access.all(),
        Access.key!(:name)
      ],
      [
        Access.key!(:targets),
        Access.filter(&match?(%Container{}, &1)),
        Access.key!(:commands),
        Access.filter(&match?(%Arg{}, &1)),
        Access.key!(:name)
      ]
    ]

    for path <- paths, reduce: cakefile do
      %Cakefile{} = cakefile ->
        update_in(cakefile, path, fn name -> prepend_namespace(name, upcase_namespace, "_") end)
    end
  end

  @spec apply_namespace_to_variable_references(Cakefile.t(), namespace()) :: Cakefile.t()
  defp apply_namespace_to_variable_references(%Cakefile{} = cakefile, namespace) do
    {global_arg_names, target_arg_names} = declared_arg_names(cakefile)
    upcase_namespace = for n <- namespace, do: String.upcase(n)

    cakefile
    |> apply_namespace_to_variable_referencing_global_args(global_arg_names, upcase_namespace)
    |> apply_namespace_to_variable_references_in_local_targets(global_arg_names, target_arg_names, upcase_namespace)
    |> apply_namespace_to_variable_references_in_container_targets(global_arg_names, target_arg_names, upcase_namespace)
  end

  @spec apply_namespace_to_variable_referencing_global_args(Cakefile.t(), arg_names(), namespace()) :: Cakefile.t()
  defp apply_namespace_to_variable_referencing_global_args(%Cakefile{} = cakefile, global_arg_names, upcase_namespace) do
    global_args_paths = [
      [
        Access.key!(:args),
        Access.filter(&(&1.default_value != nil)),
        Access.key!(:default_value)
      ],
      [
        Access.key!(:includes),
        Access.all(),
        Access.key!(:args),
        Access.filter(&(&1.default_value != nil)),
        Access.key!(:default_value)
      ]
    ]

    for path <- global_args_paths, reduce: cakefile do
      %Cakefile{} = cakefile ->
        update_in(cakefile, path, fn string ->
          replace_vars(string, fn full_match, variable, default_value ->
            apply_namespace_to_variable_name(full_match, variable, default_value, upcase_namespace, global_arg_names)
          end)
        end)
    end
  end

  @spec apply_namespace_to_variable_references_in_local_targets(
          Cakefile.t(),
          arg_names(),
          target_arg_names(),
          namespace()
        ) :: Cakefile.t()
  defp apply_namespace_to_variable_references_in_local_targets(
         %Cakefile{} = cakefile,
         global_arg_names,
         target_arg_names,
         upcase_namespace
       ) do
    local_target_args_paths = [
      [
        Access.key!(:interpreter)
      ],
      [
        Access.key!(:script)
      ],
      [
        Access.key!(:env),
        Access.filter(&(&1.default_value != nil)),
        Access.key!(:default_value)
      ],
      [
        Access.key!(:directives),
        Access.filter(&match?(%When{}, &1)),
        Access.key!(:condition)
      ]
    ]

    for %Local{tgid: tgid} <- cakefile.targets, path <- local_target_args_paths, reduce: cakefile do
      %Cakefile{} = cakefile ->
        path = [Access.key!(:targets), Access.find(&(&1.tgid == tgid))] ++ path

        update_in(cakefile, path, fn string ->
          replace_vars(string, fn full_match, variable, default_value ->
            known_arg_names = MapSet.union(global_arg_names, target_arg_names[tgid])
            apply_namespace_to_variable_name(full_match, variable, default_value, upcase_namespace, known_arg_names)
          end)
        end)
    end
  end

  @spec apply_namespace_to_variable_references_in_container_targets(
          Cakefile.t(),
          arg_names(),
          target_arg_names(),
          namespace()
        ) :: Cakefile.t()
  defp apply_namespace_to_variable_references_in_container_targets(
         %Cakefile{} = cakefile,
         global_arg_names,
         target_arg_names,
         upcase_namespace
       ) do
    container_args_paths = [
      [
        Access.key!(:directives),
        Access.filter(&match?(%When{}, &1)),
        Access.key!(:condition)
      ],
      [
        Access.key!(:directives),
        Access.filter(&match?(%Output{}, &1)),
        Access.key!(:path)
      ],
      [
        Access.key!(:commands),
        Access.filter(&(match?(%Arg{}, &1) and &1.default_value != nil)),
        Access.key!(:default_value)
      ],
      [
        Access.key!(:commands),
        Access.filter(&match?(%From{}, &1)),
        Access.key!(:image)
      ],
      [
        Access.key!(:commands),
        Access.filter(&match?(%Command{}, &1)),
        Access.key!(:arguments)
      ],
      [
        Access.key!(:commands),
        Access.filter(&match?(%Command{}, &1)),
        Access.key!(:options),
        Access.all(),
        Access.key!(:value)
      ]
    ]

    for %Container{tgid: tgid} <- cakefile.targets, path <- container_args_paths, reduce: cakefile do
      %Cakefile{} = cakefile ->
        path = [Access.key!(:targets), Access.find(&(&1.tgid == tgid))] ++ path

        update_in(cakefile, path, fn string ->
          replace_vars(string, fn full_match, variable, default_value ->
            known_arg_names = MapSet.union(global_arg_names, target_arg_names[tgid])
            apply_namespace_to_variable_name(full_match, variable, default_value, upcase_namespace, known_arg_names)
          end)
        end)
    end
  end

  @spec apply_namespace_to_target_names(Cakefile.t(), namespace()) :: Cakefile.t()
  defp apply_namespace_to_target_names(%Cakefile{} = cakefile, namespace) do
    paths = [
      [
        Access.key!(:targets),
        Access.all(),
        Access.key!(:tgid)
      ],
      [
        Access.key!(:targets),
        Access.all(),
        Access.key!(:deps_tgids),
        Access.all()
      ]
    ]

    for path <- paths, reduce: cakefile do
      %Cakefile{} = cakefile ->
        update_in(cakefile, path, fn tgid -> prepend_namespace(tgid, namespace, ".") end)
    end
  end

  @spec apply_namespace_to_target_references(Cakefile.t(), namespace()) :: Cakefile.t()
  defp apply_namespace_to_target_references(%Cakefile{} = cakefile, namespace) do
    paths = [
      [
        Access.key!(:targets),
        Access.filter(&match?(%Container{}, &1)),
        Access.key!(:commands),
        Access.filter(&match?(%From{image: "+" <> _}, &1)),
        Access.key!(:image)
      ],
      [
        Access.key!(:targets),
        Access.filter(&match?(%Container{}, &1)),
        Access.key!(:commands),
        Access.filter(&match?(%Command{instruction: "COPY"}, &1)),
        Access.key!(:options),
        Access.filter(&(match?("from", &1.name) and match?("+" <> _, &1.value))),
        Access.key!(:value)
      ]
    ]

    for path <- paths, reduce: cakefile do
      %Cakefile{} = cakefile ->
        update_in(cakefile, path, fn "+" <> image -> "+" <> prepend_namespace(image, namespace, ".") end)
    end
  end

  @spec apply_namespace_to_include_args(Cakefile.t(), namespace()) :: Cakefile.t()
  defp apply_namespace_to_include_args(%Cakefile{} = cakefile, namespace) do
    upcase_namespace = for n <- namespace, do: String.upcase(n)

    update_in(
      cakefile,
      [Access.key!(:includes), Access.all()],
      fn %Include{} = include ->
        args =
          for %Arg{} = arg <- include.args do
            include_upcase_namespace = String.upcase(include.namespace)
            name = prepend_namespace(arg.name, upcase_namespace ++ [include_upcase_namespace], "_")

            %Arg{arg | name: name}
          end

        %Include{include | args: args}
      end
    )
  end

  @spec declared_arg_names(Cakefile.t()) :: {global_arg_names :: arg_names(), target_arg_names()}
  defp declared_arg_names(%Cakefile{} = cakefile) do
    global_arg_names =
      cakefile
      |> get_in([Access.key!(:args), Access.all(), Access.key(:name)])
      |> MapSet.new()

    target_arg_names =
      cakefile.targets
      |> Enum.filter(&(match?(%Container{}, &1) or match?(%Local{}, &1)))
      |> Map.new(fn
        %Container{tgid: tgid, commands: commands} ->
          args = for %Arg{name: name} <- commands, into: MapSet.new(), do: name
          {tgid, args}

        %Local{tgid: tgid, env: env} ->
          envs = for %Env{name: name} <- env, into: MapSet.new(), do: name
          {tgid, envs}
      end)

    {global_arg_names, target_arg_names}
  end

  @spec args_list_to_map([Arg.t()]) :: args()
  defp args_list_to_map(args) do
    Map.new(args, &{&1.name, &1.default_value})
  end

  @spec args_map_to_list(args()) :: [Arg.t()]
  defp args_map_to_list(args) do
    for {name, value} <- args, do: %Arg{name: name, default_value: value}
  end

  @spec prepend_namespace(String.t(), namespace(), String.t()) :: String.t()
  defp prepend_namespace(s, namespace, joiner) do
    parts =
      case s do
        "+" <> target -> ["+"] ++ namespace ++ [target]
        "_" <> priv_var -> [""] ++ namespace ++ [priv_var]
        var -> namespace ++ [var]
      end

    Enum.join(parts, joiner)
  end

  @spec apply_namespace_to_variable_name(
          full_match :: String.t(),
          variable :: String.t(),
          default_value :: nil | String.t(),
          namespace(),
          arg_names()
        ) :: String.t()
  defp apply_namespace_to_variable_name(full_match, variable, default_value, upcase_namespace, known_arg_names) do
    fq_variable = prepend_namespace(variable, upcase_namespace, "_")

    if fq_variable in known_arg_names do
      if default_value == nil do
        "$#{fq_variable}"
      else
        "${#{fq_variable}:-#{default_value}}"
      end
    else
      # coveralls-ignore-start
      full_match
      # coveralls-ignore-stop
    end
  end

  @spec replace_vars(
          String.t(),
          (full_match :: String.t(), variable :: String.t(), default_value :: nil | String.t() -> String.t())
        ) :: String.t()
  defp replace_vars(string, replacement_fn) do
    string =
      Regex.replace(~r/\$(\w+)/, string, fn full_match, variable ->
        replacement_fn.(full_match, variable, nil)
      end)

    string =
      Regex.replace(~r/\$\{(\w+)(?::-(.*))?\}/, string, fn full_match, variable, default ->
        replacement_fn.(full_match, variable, default)
      end)

    string
  end
end
