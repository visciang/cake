Mox.defmock(Test.ContainerMock, for: Cake.Pipeline.Behaviour.Container)
Application.put_env(:cake, :container_behaviour, Test.ContainerMock)

Mox.defmock(Test.LocalMock, for: Cake.Pipeline.Behaviour.Local)
Application.put_env(:cake, :local_behaviour, Test.LocalMock)

Mox.defmock(Test.SystemBehaviourMock, for: Cake.SystemBehaviour)
Application.put_env(:cake, :system_behaviour, Test.SystemBehaviourMock)

ExUnit.start(capture_log: true, assert_receive_timeout: 1_000, refute_receive_timeout: 1_000)
