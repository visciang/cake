defmodule Test.Cake.Parser do
  use ExUnit.Case, async: true

  alias Cake.Parser
  alias Cake.Parser.Target.{Alias, Container, Local}

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

      target_with_explicit_deps: a b c
          FROM image

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
          %Alias{
            tgid: "target_alias",
            deps_tgids: ["target_with_only_from", "target_with_commands"]
          },
          %Container{
            tgid: "target_with_explicit_deps",
            included_from_ref: nil,
            directives: [],
            commands: [
              %Cake.Parser.Target.Container.From{image: "image", as: nil}
            ],
            deps_tgids: ["a", "b", "c"]
          },
          %Container{
            tgid: "target_with_only_from",
            included_from_ref: nil,
            directives: [],
            commands: [
              %Container.From{image: "image", as: nil}
            ],
            deps_tgids: []
          },
          %Container{
            tgid: "target_with_commands",
            included_from_ref: nil,
            directives: [],
            commands: [
              %Container.From{image: "image", as: nil},
              %Container.Command{instruction: "RUN", options: [], arguments: "run_1"},
              %Container.Command{instruction: "RUN", options: [], arguments: "run_2"}
            ],
            deps_tgids: []
          },
          %Container{
            tgid: "target_with_command_options",
            included_from_ref: nil,
            directives: [],
            commands: [
              %Container.From{image: "image", as: nil},
              %Container.Command{
                instruction: "COPY",
                options: [%Container.Command.Option{name: "from", value: "copy_from"}],
                arguments: "/xxx ."
              }
            ],
            deps_tgids: []
          },
          %Container{
            tgid: "target_with_args",
            included_from_ref: nil,
            directives: [],
            commands: [
              %Container.From{image: "image", as: nil},
              %Container.Arg{name: "arg_1", default_value: "arg_default_value_1"},
              %Container.Arg{name: "arg_2", default_value: "arg_default_value_2 quoted"}
            ],
            deps_tgids: []
          },
          %Container{
            tgid: "target_command_with_continuation",
            included_from_ref: nil,
            directives: [],
            commands: [
              %Container.From{image: "image", as: nil},
              %Container.Command{instruction: "RUN", arguments: "aaa         bbb", options: []}
            ],
            deps_tgids: []
          },
          %Container{
            tgid: "target_with_directives",
            included_from_ref: nil,
            directives: [
              %Parser.Directive.DevShell{},
              %Parser.Directive.Push{},
              %Parser.Directive.Output{path: "output"}
            ],
            commands: [%Container.From{image: "image", as: nil}],
            deps_tgids: []
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
              %Container.Arg{name: "ARG1", default_value: "1"},
              %Container.Arg{name: "ARG2", default_value: "2"}
            ]
          }
        ],
        path: @path,
        targets: [
          %Container{
            tgid: "target",
            included_from_ref: nil,
            directives: [],
            commands: [%Container.From{image: "image", as: nil}],
            deps_tgids: []
          }
        ]
      }

      assert {:ok, expected_res} == Parser.parse(cakefile, @path)
    end

    test "comments" do
      cakefile = """
      # comment

      ARG a
      # comment

      target_local:
          # comment
          LOCAL /bin/sh
          # comment
          ENV XXX
          ENV YYY=123
          
          # comment
          echo "${XXX}"

      target_alias: target_with_only_from target_with_commands

      # comment
      target_container:
          
          # comment
          
          @output ./xxx
          
          # comment
          
          FROM image
          # comment
          RUN true
          
          # comment


      # comment
      """

      expected_res =
        %Parser.Cakefile{
          path: @path,
          includes: [],
          args: [%Container.Arg{name: "a", default_value: nil}],
          targets: [
            %Local{
              tgid: "target_local",
              interpreter: "/bin/sh",
              script: "\necho \"${XXX}\"\n",
              deps_tgids: [],
              env: [
                %Container.Env{name: "XXX", default_value: nil},
                %Container.Env{name: "YYY", default_value: "123"}
              ],
              included_from_ref: nil
            },
            %Alias{
              tgid: "target_alias",
              deps_tgids: ["target_with_only_from", "target_with_commands"]
            },
            %Container{
              tgid: "target_container",
              commands: [
                %Container.From{image: "image", as: nil},
                %Container.Command{
                  instruction: "RUN",
                  arguments: "true",
                  options: []
                }
              ],
              deps_tgids: [],
              included_from_ref: nil,
              directives: [%Parser.Directive.Output{path: "./xxx"}]
            }
          ]
        }

      assert {:ok, expected_res} == Parser.parse(cakefile, @path)
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
        bad target identifier:
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
