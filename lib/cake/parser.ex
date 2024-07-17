defmodule Cake.Parser do
  import NimbleParsec

  alias Cake.Parser.Cakefile
  alias Cake.Parser.Directive.{DevShell, Include, Output, Push}
  alias Cake.Parser.Target.{Alias, Container}

  @type result ::
          {:ok, Cakefile.t()}
          | {:error, {context :: String.t(), line :: pos_integer(), column :: pos_integer()}}

  nl = string("\n")
  line = utf8_string([not: ?\n], min: 0)
  space = string(" ") |> optional(ignore(string("\\\n")))
  spaces = times(space, min: 1)
  indent = string("    ")

  comment =
    string("#")
    |> concat(line)

  ignorable_line =
    choice([nl, comment])

  quoted_literal_value =
    ignore(string("\""))
    |> repeat(
      lookahead_not(string("\""))
      |> choice([
        string(~S/\"/) |> replace(~S/"/),
        utf8_char([])
      ])
    )
    |> ignore(string("\""))
    |> reduce({List, :to_string, []})

  non_quoted_literal_value =
    utf8_string([not: ?\s, not: ?\n], min: 1)

  literal_value =
    choice([
      quoted_literal_value,
      non_quoted_literal_value
    ])

  target_id =
    utf8_char([?a..?z])
    |> optional(utf8_string([?a..?z, ?A..?Z, ?0..?9, ?., ?-, ?_], min: 1))
    |> reduce({List, :to_string, []})

  command_id =
    utf8_string([?A..?Z], min: 1)

  command_args =
    repeat(
      choice([
        ignore(string("\\\n")),
        utf8_char(not: ?\n)
      ])
    )
    |> reduce({List, :to_string, []})

  command_option_id =
    utf8_char([?a..?z])
    |> optional(utf8_string([?a..?z, ?A..?Z, ?0..?9, ?_], min: 1))
    |> reduce({List, :to_string, []})

  command_option =
    ignore(string("--"))
    |> unwrap_and_tag(command_option_id, :name)
    |> ignore(string("="))
    |> unwrap_and_tag(literal_value, :value)
    |> wrap()
    |> map({:cast, [Container.Command.Option]})

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
    |> map({:cast, [Container.Command]})

  arg_name =
    utf8_char([?_, ?a..?z, ?A..?Z])
    |> optional(utf8_string([?a..?z, ?A..?Z, ?0..?9, ?_], min: 1))
    |> reduce({List, :to_string, []})

  arg_value =
    ignore(string("="))
    |> concat(literal_value)

  from =
    ignore(string("FROM"))
    |> ignore(spaces)
    |> unwrap_and_tag(literal_value, :image)
    |> optional(
      ignore(spaces)
      |> ignore(string("AS"))
      |> ignore(spaces)
      |> unwrap_and_tag(target_id, :as)
    )
    |> wrap()
    |> map({:cast, [Container.From]})

  arg =
    ignore(string("ARG"))
    |> ignore(spaces)
    |> unwrap_and_tag(arg_name, :name)
    |> optional(unwrap_and_tag(arg_value, :default_value))
    |> wrap()
    |> map({:cast, [Container.Arg]})

  target_body_command =
    ignore(indent)
    |> choice([
      arg,
      from,
      command,
      ignore(comment),
      ignore(empty())
    ])

  target_commands =
    target_body_command
    |> repeat(
      ignore(nl)
      |> concat(target_body_command)
    )

  output_directive =
    ignore(string("@output"))
    |> ignore(spaces)
    |> unwrap_and_tag(line, :path)
    |> wrap()
    |> map({:cast, [Output]})

  push_directive =
    ignore(string("@push"))
    |> wrap()
    |> map({:cast, [Push]})

  include_args =
    repeat(
      ignore(spaces)
      |> unwrap_and_tag(arg_name, :name)
      |> optional(unwrap_and_tag(arg_value, :default_value))
      |> wrap()
      |> map({:cast, [Container.Arg]})
    )

  devshell_directive =
    ignore(string("@devshell"))
    |> wrap()
    |> map({:cast, [DevShell]})

  target_directive =
    ignore(indent)
    |> choice([
      output_directive,
      push_directive,
      devshell_directive
    ])

  target_directives =
    target_directive
    |> repeat(
      ignore(nl)
      |> concat(target_directive)
    )

  target_container =
    unwrap_and_tag(target_id, :tgid)
    |> ignore(string(":"))
    |> ignore(nl)
    |> optional(
      tag(target_directives, :directives)
      |> ignore(nl)
    )
    |> optional(tag(target_commands, :commands))
    |> wrap()
    |> map({:cast, [Container]})

  alias_targets =
    target_id
    |> repeat(
      ignore(spaces)
      |> concat(target_id)
    )

  target_alias =
    unwrap_and_tag(target_id, :tgid)
    |> ignore(string(":"))
    |> ignore(spaces)
    |> tag(alias_targets, :tgids)
    |> wrap()
    |> map({:cast, [Alias]})

  target =
    choice([
      target_alias,
      target_container
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

  include_directive =
    ignore(string("@include"))
    |> ignore(spaces)
    |> unwrap_and_tag(literal_value, :ref)
    |> optional(tag(include_args, :args))
    |> wrap()
    |> map({:cast, [Include]})

  include_directives =
    include_directive
    |> repeat(
      ignore(nl)
      |> ignore(repeat(ignorable_line))
      |> concat(include_directive)
    )

  cakefile =
    ignore(repeat(ignorable_line))
    |> optional(tag(global_args, :args))
    |> ignore(repeat(ignorable_line))
    |> optional(
      tag(
        include_directives
        |> ignore(nl),
        :includes
      )
    )
    |> ignore(repeat(ignorable_line))
    |> optional(tag(targets, :targets))
    |> ignore(repeat(ignorable_line))
    |> eos()
    |> wrap()
    |> map({:cast, [Cakefile]})

  defparsec :cakefile, cakefile

  @spec parse(String.t(), Path.t()) :: result()
  def parse(content, path) do
    content
    |> cakefile()
    |> case do
      {:ok, [cakefile], "" = _rest, _context, _position, _byte_offset} ->
        {:ok, %Cakefile{cakefile | path: path}}

      {:error, _reason, _rest, _context, {line, offset_to_start_of_line}, byte_offset} ->
        column = byte_offset - offset_to_start_of_line
        {:error, {content, line, column}}
    end
  end

  @spec cast(Keyword.t(), module()) :: struct()
  defp cast(fields, module) do
    struct!(module, fields)
  end
end
