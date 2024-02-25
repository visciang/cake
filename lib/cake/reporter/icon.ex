# coveralls-ignore-start

defmodule Cake.Reporter.Icon do
  def ok, do: [:green, "✔", :reset]
  def error, do: [:red, "✘", :reset]
  def timeout, do: "⏰"
  def output, do: [:yellow, "←", :reset]
  def log, do: "…"
  def notice, do: "!"
end

# coveralls-ignore-stop
