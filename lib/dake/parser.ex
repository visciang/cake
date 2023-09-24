defmodule Dake.Parser do
  @moduledoc """
  `Dakefile` parser.
  """

  alias Dake.Parser.{Dakefile, Docker, Target}

  import NimbleParsec

  @type result ::
          {:ok, Dakefile.t()}
          | {:error, {context :: String.t(), line :: pos_integer(), column :: pos_integer()}}

  nl = string("\n")
  line = utf8_string([not: ?\n], min: 1)
  space = string(" ")
  spaces = times(space, min: 1)
  indent = string("    ")

  comment =
    string("#")
    |> concat(line)

  ignorable_line =
    choice([nl, comment])

  dake_command_id =
    string("DAKE_")
    |> utf8_string([?A..?Z], min: 1)
    |> reduce({List, :to_string, []})

  command_id =
    choice([
      dake_command_id,
      utf8_string([?A..?Z], min: 1)
    ])

  command_args =
    repeat(
      lookahead_not(nl)
      |> choice([
        ignore(string("\\\n")),
        utf8_char([])
      ])
    )
    |> reduce({List, :to_string, []})

  command_option =
    ignore(string("--"))
    |> unwrap_and_tag(utf8_string([?a..?z, ?A..?Z, ?0..?9, ?_], min: 1), :name)
    |> ignore(string("="))
    # TODO: value is more that just [^ ]+
    |> unwrap_and_tag(utf8_string([not: ?\s], min: 1), :value)
    |> wrap()
    |> map({:cast, [Docker.Command.Option]})

  command_options =
    command_option
    |> repeat(
      ignore(spaces)
      |> concat(command_option)
    )

  # TODO here-docs

  command =
    unwrap_and_tag(command_id, :instruction)
    |> ignore(spaces)
    |> optional(
      tag(command_options, :options)
      |> ignore(spaces)
    )
    |> unwrap_and_tag(command_args, :arguments)
    |> wrap()
    |> map({:cast, [Docker.Command]})

  dake_command_output =
    ignore(string("DAKE_OUTPUT"))
    |> ignore(spaces)
    |> unwrap_and_tag(line, :dir)
    |> wrap()
    |> map({:cast, [Docker.DakeOutput]})

  dake_command_push =
    ignore(string("DAKE_PUSH"))
    |> wrap()
    |> map({:cast, [Docker.DakePush]})

  dake_command =
    choice([
      dake_command_output,
      dake_command_push
    ])

  arg_name =
    utf8_char([?a..?z, ?A..?Z])
    |> optional(utf8_string([?a..?z, ?A..?Z, ?0..?9, ?_], min: 1))
    |> reduce({List, :to_string, []})

  arg =
    ignore(string("ARG"))
    |> ignore(spaces)
    |> unwrap_and_tag(arg_name, :name)
    |> optional(
      ignore(
        repeat(space)
        |> string("=")
        |> repeat(space)
      )
      |> unwrap_and_tag(line, :default_value)
    )
    |> wrap()
    |> map({:cast, [Docker.Arg]})

  target_id =
    utf8_char([?a..?z])
    |> optional(utf8_string([?a..?z, ?A..?Z, ?0..?9, ?., ?-, ?_], min: 1))
    |> reduce({List, :to_string, []})

  target_body_command =
    ignore(indent)
    |> choice([
      dake_command,
      command,
      arg,
      ignore(comment),
      ignore(empty())
    ])

  target_commands =
    target_body_command
    |> repeat(
      ignore(nl)
      |> concat(target_body_command)
    )

  target_docker =
    unwrap_and_tag(target_id, :target)
    |> ignore(string(":"))
    |> ignore(nl)
    |> tag(target_commands, :commands)
    |> wrap()
    |> map({:cast, [Target.Docker]})

  alias_targets =
    target_id
    |> repeat(
      ignore(spaces)
      |> concat(target_id)
    )

  target_alias =
    unwrap_and_tag(target_id, :target)
    |> ignore(string(":"))
    |> ignore(spaces)
    |> tag(alias_targets, :targets)
    |> wrap()
    |> map({:cast, [Target.Alias]})

  target =
    choice([
      target_alias,
      target_docker
    ])

  global_args =
    arg
    |> repeat(
      ignore(nl)
      |> ignore(repeat(ignorable_line))
      |> concat(arg)
    )

  targets =
    target
    |> repeat(
      ignore(nl)
      |> ignore(repeat(ignorable_line))
      |> concat(target)
    )

  dake_include =
    ignore(string("DAKE_INCLUDE"))
    |> ignore(spaces)
    |> tag(line, :target)
    |> wrap()
    |> map({:cast, [Docker.DakeInclude]})

  dake_includes =
    dake_include
    |> repeat(
      ignore(nl)
      |> ignore(repeat(ignorable_line))
      |> concat(dake_include)
    )

  dakefile =
    ignore(repeat(ignorable_line))
    |> tag(optional(dake_includes), :includes)
    |> ignore(repeat(ignorable_line))
    |> tag(optional(global_args), :args)
    |> ignore(repeat(ignorable_line))
    |> tag(targets, :targets)
    |> ignore(repeat(ignorable_line))
    |> eos()
    |> wrap()
    |> map({:cast, [Dakefile]})

  defparsec :dakefile, dakefile

  @doc """
  Parse a `Dakefile`.
  """
  @spec parse(String.t()) :: result()
  def parse(content) do
    content
    |> dos2unix()
    |> dakefile()
    |> case do
      {:ok, [dakefile], "" = _rest, _context, _position, _byte_offset} ->
        {:ok, dakefile}

      {:error, _reason, _rest, _context, {line, offset_to_start_of_line}, byte_offset} ->
        column = byte_offset - offset_to_start_of_line
        {:error, {content, line, column}}
    end
  end

  @spec dos2unix(String.t()) :: String.t()
  defp dos2unix(data) do
    String.replace(data, "\r\n", "\n")
  end

  @spec cast(Keyword.t(), module()) :: struct()
  defp cast(fields, module) do
    struct!(module, fields)
  end
end
