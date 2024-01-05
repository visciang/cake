defmodule Dask.Utils do
  @minute 60
  @hour @minute * 60
  @divisor [@hour, @minute, 1]

  @spec seconds_to_compound_duration(number(), non_neg_integer()) :: String.t()
  def seconds_to_compound_duration(sec, decimals \\ 3) do
    sec_int = trunc(sec)

    sec_decimals =
      (sec - sec_int)
      |> to_string()
      |> String.slice(2, decimals)
      |> String.pad_trailing(decimals, "0")

    {_, [s, m, h]} =
      for divisor <- @divisor, reduce: {sec_int, []} do
        {n, acc} -> {rem(n, divisor), [div(n, divisor) | acc]}
      end

    [{"#{trunc(s)}.#{sec_decimals}", "s"}, {to_string(m), "min"}, {to_string(h), "hr"}]
    |> Enum.reject(fn {n, _} -> n == "0" end)
    |> Enum.map_join(" ", fn {n, unit} -> "#{n}#{unit}" end)
  end

  # coveralls-ignore-start

  @spec dot_to_svg(iodata(), Path.t()) :: :ok
  def dot_to_svg(dot, out_file) do
    dot_tmp_file = "#{Path.rootname(out_file)}.dot"
    File.write!(dot_tmp_file, dot, [:utf8])
    {_, 0} = System.cmd("dot", ["-Tsvg", dot_tmp_file], into: File.stream!(out_file))
    File.rm!(dot_tmp_file)

    :ok
  end

  # coveralls-ignore-end
end
