Mox.defmock(Test.ContainerManagerMock, for: Cake.Pipeline.ContainerManager)
Application.put_env(:cake, :container_manager, Test.ContainerManagerMock)

Mox.defmock(Test.SystemBehaviourMock, for: Cake.SystemBehaviour)
Application.put_env(:cake, :system_behaviour, Test.SystemBehaviourMock)

ExUnit.start(capture_log: true, assert_receive_timeout: 1_000, refute_receive_timeout: 1_000)
