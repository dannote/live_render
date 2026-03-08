defmodule LiveRender.JSONRepair do
  @moduledoc """
  Repairs incomplete JSON produced during LLM streaming so partial specs
  can be rendered progressively.

  Handles three common cases when a JSON string is truncated mid-generation:
  1. Open strings — closes unmatched quotes
  2. Trailing syntax — strips dangling `,` or appends `null` after dangling `:`
  3. Unmatched brackets — closes open `{` and `[` in reverse order
  """

  @doc """
  Attempts to repair truncated JSON into something parseable.

  Returns the repaired string. The caller should attempt `Jason.decode/1`
  on the result — repair is best-effort and may still produce invalid JSON
  for some truncation points.
  """
  @spec repair(String.t()) :: String.t()
  def repair(incomplete) do
    incomplete
    |> close_open_string()
    |> strip_trailing_syntax()
    |> close_brackets()
  end

  defp close_open_string(s) do
    quote_count =
      s |> String.replace(~r/\\"/, "") |> String.graphemes() |> Enum.count(&(&1 == "\""))

    if rem(quote_count, 2) == 1, do: s <> "\"", else: s
  end

  defp strip_trailing_syntax(s) do
    trimmed = String.trim_trailing(s)

    cond do
      String.ends_with?(trimmed, ":") -> trimmed <> "null"
      String.ends_with?(trimmed, ",") -> String.slice(trimmed, 0..-2//1)
      true -> trimmed
    end
  end

  defp close_brackets(s) do
    chars = String.graphemes(s)

    {opens, _} =
      Enum.reduce(chars, {[], false}, fn
        "\"", {stack, false} -> {stack, true}
        "\"", {stack, true} -> {stack, false}
        "{", {stack, false} -> {[:obj | stack], false}
        "[", {stack, false} -> {[:arr | stack], false}
        "}", {[:obj | rest], false} -> {rest, false}
        "]", {[:arr | rest], false} -> {rest, false}
        _, acc -> acc
      end)

    closers = Enum.map(opens, fn :obj -> "}"; :arr -> "]" end)
    s <> Enum.join(closers)
  end
end
