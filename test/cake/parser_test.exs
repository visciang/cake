defmodule Test.Cake do
  use ExUnit.Case, async: true

  alias Cake.Parser

  @path "a/path"

  describe "ok" do
    test "empty" do
      cakefile = ""

      expected_res = %Parser.Cakefile{
        path: @path,
        includes: [],
        args: [],
        targets: []
      }

      assert {:ok, expected_res} == Parser.parse(cakefile, @path)
    end

    test "targets and commands" do
      cakefile = """
      target_alias: target_with_only_from target_with_commands

      target_with_only_from:
          FROM image

      target_with_commands:
          FROM image
          RUN run_1
          RUN run_2

      target_with_command_options:
          FROM image
          COPY --from=copy_from /xxx .

      target_with_args:
          FROM image
          ARG arg_1=arg_default_value_1
          ARG arg_2="arg_default_value_2 quoted"

      target_command_with_continuation:
          FROM image
          RUN aaa \
              bbb

      target_with_directives:
          @devshell
          @push
          @output output
          FROM image
      """

      expected_res = %Parser.Cakefile{
        path: @path,
        includes: [],
        args: [],
        targets: [
          %Parser.Alias{
            tgid: "target_alias",
            tgids: ["target_with_only_from", "target_with_commands"]
          },
          %Parser.Target{
            tgid: "target_with_only_from",
            included_from_ref: nil,
            directives: [],
            commands: [
              %Parser.Container.From{image: "image", as: nil}
            ]
          },
          %Parser.Target{
            tgid: "target_with_commands",
            included_from_ref: nil,
            directives: [],
            commands: [
              %Parser.Container.From{image: "image", as: nil},
              %Parser.Container.Command{instruction: "RUN", options: [], arguments: "run_1"},
              %Parser.Container.Command{instruction: "RUN", options: [], arguments: "run_2"}
            ]
          },
          %Parser.Target{
            tgid: "target_with_command_options",
            included_from_ref: nil,
            directives: [],
            commands: [
              %Parser.Container.From{image: "image", as: nil},
              %Parser.Container.Command{
                instruction: "COPY",
                options: [%Parser.Container.Command.Option{name: "from", value: "copy_from"}],
                arguments: "/xxx ."
              }
            ]
          },
          %Parser.Target{
            tgid: "target_with_args",
            included_from_ref: nil,
            directives: [],
            commands: [
              %Parser.Container.From{image: "image", as: nil},
              %Parser.Container.Arg{name: "arg_1", default_value: "arg_default_value_1"},
              %Parser.Container.Arg{name: "arg_2", default_value: "arg_default_value_2 quoted"}
            ]
          },
          %Parser.Target{
            tgid: "target_command_with_continuation",
            included_from_ref: nil,
            directives: [],
            commands: [
              %Parser.Container.From{image: "image", as: nil},
              %Parser.Container.Command{instruction: "RUN", arguments: "aaa         bbb", options: []}
            ]
          },
          %Parser.Target{
            tgid: "target_with_directives",
            included_from_ref: nil,
            directives: [
              %Parser.Directive.DevShell{},
              %Parser.Directive.Push{},
              %Parser.Directive.Output{path: "output"}
            ],
            commands: [%Parser.Container.From{image: "image", as: nil}]
          }
        ]
      }

      assert {:ok, expected_res} == Parser.parse(cakefile, @path)
    end

    test "include directives" do
      cakefile = """
      @include include_ref ARG1=1 ARG2=2

      target:
          FROM image
      """

      expected_res = %Parser.Cakefile{
        args: [],
        includes: [
          %Parser.Directive.Include{
            ref: "include_ref",
            args: [
              %Parser.Container.Arg{name: "ARG1", default_value: "1"},
              %Parser.Container.Arg{name: "ARG2", default_value: "2"}
            ]
          }
        ],
        path: "a/path",
        targets: [
          %Parser.Target{
            tgid: "target",
            included_from_ref: nil,
            directives: [],
            commands: [%Parser.Container.From{image: "image", as: nil}]
          }
        ]
      }

      assert {:ok, expected_res} == Parser.parse(cakefile, @path)
    end

    test "comments" do
      cakefile = """
      # comment
      target_alias: target_with_only_from target_with_commands

      # comment
      target_with_only_from:
          # comment
          FROM image
          # comment

      # comment
      """

      assert {:ok, _} = Parser.parse(cakefile, @path)
    end
  end

  describe "error" do
    test "comments" do
      cakefiles = [
        """
        target_alias: target_with_only_from target_with_commands # bad comment position
        """,
        """
        target: # bad comment position
          FROM image
        """,
        """
        target:
          FROM image # bad comment position
        """
      ]

      for cakefile <- cakefiles do
        assert {:error, _} = Parser.parse(cakefile, @path)
      end
    end

    test "targets" do
      cakefiles = [
        """
        empty target:
        """,
        """
        missing_from:
          RUN run
        """,
        """
        bad_indentation:
        FROM image
        """
      ]

      for cakefile <- cakefiles do
        assert {:error, _} = Parser.parse(cakefile, @path)
      end
    end
  end
end
