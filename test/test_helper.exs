Mox.defmock(Test.ContainerManagerMock, for: Cake.Pipeline.ContainerManager)
Application.put_env(:cake, :container_manager, Test.ContainerManagerMock)

ExUnit.start(capture_log: true)
