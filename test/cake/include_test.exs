defmodule Test.Cake.Include do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import Mox
  require Test.Support

  alias Cake.Parser.Cakefile
  alias Cake.Parser.Directive.When
  alias Cake.Parser.Target.{Alias, Container, Local}
  alias Cake.Parser.Target.Container.{Arg, Command, From}
  alias Cake.Parser.Target.Container.Command.Option

  @moduletag :tmp_dir
  setup {Test.Support, :setup_cake_run}

  test "included Cakefile does not exists" do
    File.mkdir_p!("./dir")

    Test.Support.write_cakefile("""
    @include ./dir NAMESPACE nnn
    """)

    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :error
      assert msg == "Preprocessing error:\n\"Cannot find Cakefile in include from ./dir\""
      :ok
    end)

    {result, _output} =
      with_io(fn ->
        Cake.main(["ast"])
      end)

    assert result == :ok
  end

  test "included Cakefile from non existing local directory" do
    Test.Support.write_cakefile("""
    @include ./dir NAMESPACE nnn
    """)

    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :error
      assert msg == "Preprocessing error:\n\"@include ./dir failed: directory not found\""
      :ok
    end)

    {result, _output} =
      with_io(fn ->
        Cake.main(["ast"])
      end)

    assert result == :ok
  end

  test "included Cakefile from local directory" do
    Test.Support.write_cakefile("""
    ARG arg

    @include ./dir NAMESPACE nnn

    target:
        FROM scratch
    """)

    Test.Support.write_cakefile("dir", """
    ARG inc_arg

    all: inc_target_1 inc_target_2

    inc_target_1:
        FROM scratch

    inc_target_2:
        FROM scratch
    """)

    expect(Test.SystemBehaviourMock, :halt, fn exit_status, ast ->
      assert exit_status == :ok

      assert %Cakefile{
               path: "Cakefile",
               args: [
                 %Arg{name: "NNN_inc_arg"},
                 %Arg{name: "arg"}
               ],
               targets: [
                 %Alias{
                   tgid: "nnn.all",
                   deps_tgids: ["nnn.inc_target_1", "nnn.inc_target_2"]
                 },
                 %Container{
                   tgid: "nnn.inc_target_1"
                 },
                 %Container{
                   tgid: "nnn.inc_target_2"
                 },
                 %Container{
                   tgid: "target"
                 }
               ]
             } = ast

      :ok
    end)

    :ok = Cake.main(["ast"])
  end

  test "included Cakefile outside the current project workdir" do
    Test.Support.write_cakefile("project_dir", """
    ARG arg

    @include ../dir NAMESPACE nnn

    target:
        FROM scratch
    """)

    Test.Support.write_cakefile("dir", """
    ARG inc_arg

    all: inc_target_1 inc_target_2

    inc_target_1:
        FROM scratch

    inc_target_2:
        FROM scratch
    """)

    expect(Test.SystemBehaviourMock, :halt, fn exit_status, ast ->
      assert exit_status == :ok

      assert %Cakefile{
               path: "Cakefile",
               args: [
                 %Arg{name: "NNN_inc_arg"},
                 %Arg{name: "arg"}
               ],
               targets: [
                 %Alias{
                   tgid: "nnn.all",
                   deps_tgids: ["nnn.inc_target_1", "nnn.inc_target_2"]
                 },
                 %Container{
                   tgid: "nnn.inc_target_1"
                 },
                 %Container{
                   tgid: "nnn.inc_target_2"
                 },
                 %Container{
                   tgid: "target"
                 }
               ]
             } = ast

      :ok
    end)

    :ok = Cake.main(["ast", "--workdir", "project_dir"])
  end

  test "included Cakefile outside the current exec dir" do
    Test.Support.write_cakefile("project_dir", """
    ARG arg

    @include ../dir NAMESPACE nnn

    target:
        FROM scratch
    """)

    Test.Support.write_cakefile("dir", """
    ARG inc_arg

    all: inc_target_1 inc_target_2

    inc_target_1:
        FROM scratch

    inc_target_2:
        FROM scratch
    """)

    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert msg ==
               "Preprocessing error:\n\"@include ../dir failed: './../dir' is not a sub-directory of the cake execution directory\""

      assert exit_status == :error
      :ok
    end)

    File.cd!("project_dir", fn ->
      :ok = Cake.main(["ast"])
    end)
  end

  describe "same include under different namespaces applies namespace to" do
    test "targets" do
      Test.Support.write_cakefile("""
      @include ./foo NAMESPACE foo1
      @include ./foo NAMESPACE foo2

      all: foo1.all foo2.all target

      target: foo1.target_f foo2.target_f
          FROM scratch
      """)

      Test.Support.write_cakefile("foo", """
      all: target_f

      target_f:
          FROM scratch
      """)

      expect(Test.SystemBehaviourMock, :halt, fn exit_status, ast ->
        assert exit_status == :ok

        assert %Cakefile{
                 path: "Cakefile",
                 targets: [
                   %Alias{
                     tgid: "foo1.all",
                     deps_tgids: ["foo1.target_f"]
                   },
                   %Container{
                     tgid: "foo1.target_f",
                     deps_tgids: []
                   },
                   %Alias{
                     tgid: "foo2.all",
                     deps_tgids: ["foo2.target_f"]
                   },
                   %Container{
                     tgid: "foo2.target_f",
                     deps_tgids: []
                   },
                   %Alias{
                     tgid: "all",
                     deps_tgids: ["foo1.all", "foo2.all", "target"]
                   },
                   %Container{
                     tgid: "target",
                     deps_tgids: ["foo1.target_f", "foo2.target_f"]
                   }
                 ]
               } = ast

        :ok
      end)

      :ok = Cake.main(["ast"])
    end

    test "ARGS" do
      Test.Support.write_cakefile("""
      ARG M=m
      @include ./foo NAMESPACE foo1 ARGS FOO1_F=fm FOO1_TF=tfm
      @include ./foo NAMESPACE foo2
      @include ./foo NAMESPACE foo3 ARGS FOO3_TF=xxx

      target:
          @when [ "$M" = "" && "$TF" = "" ]
          FROM image:$F
          ARG TF=1
          RUN echo "$TF"
          COPY --from=$TF $TF .
      """)

      Test.Support.write_cakefile("foo", """
      ARG F=f

      target_f:
          @when [ "$F" = "" && "$TF" = "" ]
          FROM image:$F
          ARG TF=$F
          ARG TFD=${F:-def}
          RUN echo "$TF"
          COPY --from=$TF $TF .

      target_l:
          @when [ "$F" = "" && "$TL" = "" ]
          LOCAL /bin/sh
          ARG TL=$F
          echo "$TL"
      """)

      expect(Test.SystemBehaviourMock, :halt, fn exit_status, ast ->
        assert exit_status == :ok

        assert %Cakefile{
                 path: "Cakefile",
                 args: [
                   %Arg{name: "FOO1_F", default_value: "fm"},
                   %Arg{name: "FOO2_F", default_value: "f"},
                   %Arg{name: "FOO3_F", default_value: "from_cli_1"},
                   %Arg{name: "M", default_value: "m"}
                 ],
                 targets: [
                   %Container{
                     tgid: "foo1.target_f",
                     directives: [
                       %When{condition: "[ \"$FOO1_F\" = \"\" && \"$FOO1_TF\" = \"\" ]"}
                     ],
                     commands: [
                       %From{image: "image:$FOO1_F"},
                       %Arg{name: "FOO1_TF", default_value: "tfm"},
                       %Arg{name: "FOO1_TFD", default_value: "${FOO1_F:-def}"},
                       %Command{instruction: "RUN", arguments: "echo \"$FOO1_TF\""},
                       %Command{
                         instruction: "COPY",
                         options: [%Option{name: "from", value: "$FOO1_TF"}],
                         arguments: "$FOO1_TF ."
                       }
                     ]
                   },
                   %Local{
                     tgid: "foo1.target_l",
                     interpreter: "/bin/sh",
                     script: "\necho \"$FOO1_TL\"",
                     directives: [
                       %When{condition: "[ \"$FOO1_F\" = \"\" && \"$FOO1_TL\" = \"\" ]"}
                     ],
                     args: [%Arg{name: "FOO1_TL", default_value: "$FOO1_F"}]
                   },
                   %Container{
                     tgid: "foo2.target_f",
                     directives: [
                       %When{condition: "[ \"$FOO2_F\" = \"\" && \"$FOO2_TF\" = \"\" ]"}
                     ],
                     commands: [
                       %From{image: "image:$FOO2_F"},
                       %Arg{name: "FOO2_TF", default_value: "$FOO2_F"},
                       %Arg{name: "FOO2_TFD", default_value: "${FOO2_F:-def}"},
                       %Command{instruction: "RUN", arguments: "echo \"$FOO2_TF\""},
                       %Command{
                         instruction: "COPY",
                         options: [%Option{name: "from", value: "$FOO2_TF"}],
                         arguments: "$FOO2_TF ."
                       }
                     ]
                   },
                   %Local{
                     tgid: "foo2.target_l",
                     interpreter: "/bin/sh",
                     script: "\necho \"$FOO2_TL\"",
                     directives: [
                       %When{condition: "[ \"$FOO2_F\" = \"\" && \"$FOO2_TL\" = \"\" ]"}
                     ],
                     args: [%Arg{name: "FOO2_TL", default_value: "$FOO2_F"}]
                   },
                   %Container{
                     tgid: "foo3.target_f",
                     directives: [
                       %When{condition: "[ \"$FOO3_F\" = \"\" && \"$FOO3_TF\" = \"\" ]"}
                     ],
                     commands: [
                       %From{image: "image:$FOO3_F"},
                       %Arg{name: "FOO3_TF", default_value: "from_cli_2"},
                       %Arg{name: "FOO3_TFD", default_value: "${FOO3_F:-def}"},
                       %Command{instruction: "RUN", arguments: "echo \"$FOO3_TF\""},
                       %Command{
                         instruction: "COPY",
                         options: [%Option{name: "from", value: "$FOO3_TF"}],
                         arguments: "$FOO3_TF ."
                       }
                     ]
                   },
                   %Local{
                     tgid: "foo3.target_l",
                     interpreter: "/bin/sh",
                     script: "\necho \"$FOO3_TL\"",
                     directives: [
                       %When{condition: "[ \"$FOO3_F\" = \"\" && \"$FOO3_TL\" = \"\" ]"}
                     ],
                     args: [%Arg{name: "FOO3_TL", default_value: "$FOO3_F"}]
                   },
                   %Container{
                     tgid: "target",
                     directives: [
                       %When{condition: "[ \"$M\" = \"\" && \"$TF\" = \"\" ]"}
                     ],
                     commands: [
                       %From{image: "image:$F"},
                       %Arg{name: "TF", default_value: "1"},
                       %Command{instruction: "RUN", arguments: "echo \"$TF\""},
                       %Command{
                         instruction: "COPY",
                         options: [%Option{name: "from", value: "$TF"}],
                         arguments: "$TF ."
                       }
                     ]
                   }
                 ]
               } = ast

        :ok
      end)

      :ok = Cake.main(["ast", "FOO3_F=from_cli_1", "FOO3_TF=from_cli_2"])
    end
  end

  describe "deeply nested includes applies namespace to" do
    test "targets" do
      Test.Support.write_cakefile("""
      @include ./foo NAMESPACE foo

      target:
          FROM scratch
      """)

      Test.Support.write_cakefile("foo", """
      @include ./bar NAMESPACE bar

      target_f:
          FROM scratch
      """)

      Test.Support.write_cakefile("foo/bar", """
      target_b:
          FROM scratch
      """)

      expect(Test.SystemBehaviourMock, :halt, fn exit_status, ast ->
        assert exit_status == :ok

        assert %Cakefile{
                 path: "Cakefile",
                 targets: [
                   %Container{
                     tgid: "foo.bar.target_b",
                     deps_tgids: []
                   },
                   %Container{
                     tgid: "foo.target_f",
                     deps_tgids: []
                   },
                   %Container{
                     tgid: "target",
                     deps_tgids: []
                   }
                 ]
               } = ast

        :ok
      end)

      :ok = Cake.main(["ast"])
    end

    test "ARGS" do
      Test.Support.write_cakefile("""
      ARG ARG_0=0

      @include ./foo NAMESPACE foo

      target:
          FROM scratch
          ARG ARG_T0=0
      """)

      Test.Support.write_cakefile("foo", """
      ARG ARG_1=1

      @include ./bar NAMESPACE bar ARGS BAR_ARG_2=$ARG_1

      target_f:
          FROM scratch
          ARG ARG_T1=1
      """)

      Test.Support.write_cakefile("foo/bar", """
      ARG ARG_2=2

      target_b:
          FROM scratch
          ARG ARG_T2=2
      """)

      expect(Test.SystemBehaviourMock, :halt, fn exit_status, ast ->
        assert exit_status == :ok

        assert %Cakefile{
                 path: "Cakefile",
                 args: [
                   %Arg{name: "ARG_0", default_value: "0"},
                   %Arg{name: "FOO_ARG_1", default_value: "1"},
                   %Arg{name: "FOO_BAR_ARG_2", default_value: "$FOO_ARG_1"}
                 ],
                 targets: [
                   %Container{
                     tgid: "foo.bar.target_b",
                     commands: [
                       %From{image: "scratch"},
                       %Arg{name: "FOO_BAR_ARG_T2", default_value: "2"}
                     ]
                   },
                   %Container{
                     tgid: "foo.target_f",
                     commands: [
                       %From{image: "scratch"},
                       %Arg{name: "FOO_ARG_T1", default_value: "1"}
                     ]
                   },
                   %Container{
                     tgid: "target",
                     commands: [
                       %From{image: "scratch"},
                       %Arg{name: "ARG_T0", default_value: "0"}
                     ]
                   }
                 ]
               } = ast

        :ok
      end)

      :ok = Cake.main(["ast"])
    end
  end

  describe "include applies namespace to target with" do
    test "implicit dependencies" do
      Test.Support.write_cakefile("""
      @include ./foo NAMESPACE foo

      all: foo.all target

      target: foo.target_2
          FROM scratch
      """)

      Test.Support.write_cakefile("foo", """
      all: target_1 target_2

      target_1:
          FROM scratch

      target_2:
          FROM scratch

      target_3: target_1
          FROM scratch
      """)

      expect(Test.SystemBehaviourMock, :halt, fn exit_status, ast ->
        assert exit_status == :ok

        assert %Cakefile{
                 path: "Cakefile",
                 targets: [
                   %Alias{
                     tgid: "foo.all",
                     deps_tgids: ["foo.target_1", "foo.target_2"]
                   },
                   %Container{
                     tgid: "foo.target_1",
                     deps_tgids: []
                   },
                   %Container{
                     tgid: "foo.target_2",
                     deps_tgids: []
                   },
                   %Container{
                     tgid: "foo.target_3",
                     deps_tgids: ["foo.target_1"]
                   },
                   %Alias{
                     tgid: "all",
                     deps_tgids: ["foo.all", "target"]
                   },
                   %Container{
                     tgid: "target",
                     deps_tgids: ["foo.target_2"]
                   }
                 ]
               } = ast

        :ok
      end)

      :ok = Cake.main(["ast"])
    end

    test "explicit dependencies" do
      Test.Support.write_cakefile("""
      @include ./foo NAMESPACE foo

      target:
          FROM +foo.target_1
          COPY --from=+foo.target_2 /target_2 /target_2
      """)

      Test.Support.write_cakefile("foo", """
      target_1:
          FROM alpine
          RUN touch /target_1

      target_2:
          FROM alpine
          RUN touch /target_2
          
      target_3:
          FROM +target_1
          COPY --from=+target_2 /target_2 /target_2
      """)

      expect(Test.SystemBehaviourMock, :halt, fn exit_status, ast ->
        assert exit_status == :ok

        assert %Cakefile{
                 path: "Cakefile",
                 targets: [
                   %Container{
                     commands: [
                       %From{image: "alpine"},
                       %Command{instruction: "RUN", arguments: "touch /target_1"}
                     ],
                     deps_tgids: [],
                     tgid: "foo.target_1"
                   },
                   %Container{
                     commands: [
                       %From{image: "alpine"},
                       %Command{instruction: "RUN", arguments: "touch /target_2"}
                     ],
                     deps_tgids: [],
                     tgid: "foo.target_2"
                   },
                   %Container{
                     commands: [
                       %From{image: "+foo.target_1"},
                       %Command{
                         instruction: "COPY",
                         arguments: "/target_2 /target_2",
                         options: [%Option{name: "from", value: "+foo.target_2"}]
                       }
                     ],
                     deps_tgids: [],
                     tgid: "foo.target_3"
                   },
                   %Container{
                     deps_tgids: [],
                     tgid: "target",
                     commands: [
                       %From{image: "+foo.target_1"},
                       %Command{
                         instruction: "COPY",
                         arguments: "/target_2 /target_2",
                         options: [%Option{name: "from", value: "+foo.target_2"}]
                       }
                     ]
                   }
                 ]
               } = ast

        :ok
      end)

      :ok = Cake.main(["ast"])
    end
  end

  describe "conflicting" do
    test "targets" do
      Test.Support.write_cakefile("""
      @include ./foo NAMESPACE foo

      all: foo.all foo.target

      foo.target:
          FROM scratch
      """)

      Test.Support.write_cakefile("foo", """
      target:
          FROM scratch
      """)

      expect(Test.SystemBehaviourMock, :halt, fn exit_status, exit_reason ->
        assert exit_status == :error

        assert exit_reason ==
                 "Preprocessing error:\n\"target foo.target: defined in [\\\"Cakefile\\\", \\\"././foo/Cakefile\\\"]\""

        :ok
      end)

      :ok = Cake.main(["ast"])
    end

    test "ARGS" do
      Test.Support.write_cakefile("""
      ARG FOO_A

      @include ./foo NAMESPACE foo
      """)

      Test.Support.write_cakefile("foo", """
      ARG A
      """)

      expect(Test.SystemBehaviourMock, :halt, fn exit_status, exit_reason ->
        assert exit_status == :error

        assert exit_reason ==
                 "Preprocessing error:\n\"ARG FOO_A: defined in [\\\"Cakefile\\\", \\\"././foo/Cakefile\\\"]\""

        :ok
      end)

      :ok = Cake.main(["ast"])
    end
  end
end
