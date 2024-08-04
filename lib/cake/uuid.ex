defmodule Cake.UUID do
  @spec new :: String.t()
  def new do
    Base.encode32(:crypto.strong_rand_bytes(16), case: :lower, padding: false)
  end
end
