defmodule LiveRender.Format.OpenUILang.Tokenizer do
  @moduledoc false

  @type token ::
          {:identifier, String.t()}
          | {:string, String.t()}
          | {:number, number()}
          | true
          | false
          | :null
          | :lparen
          | :rparen
          | :lbracket
          | :rbracket
          | :lbrace
          | :rbrace
          | :comma
          | :colon
          | :equals
          | :newline

  @spec tokenize(String.t()) :: {:ok, [token()]} | {:error, String.t()}
  def tokenize(input) do
    tokenize(input, [])
  end

  defp tokenize("", acc), do: {:ok, Enum.reverse(acc)}

  defp tokenize(<<c, rest::binary>>, acc) when c in ~c[ \t\r] do
    tokenize(rest, acc)
  end

  defp tokenize(<<?/, ?/, rest::binary>>, acc) do
    {_comment, rest} = skip_line(rest)
    tokenize(rest, acc)
  end

  defp tokenize(<<?\n, rest::binary>>, acc) do
    tokenize(rest, [:newline | acc])
  end

  defp tokenize(<<?=, rest::binary>>, acc), do: tokenize(rest, [:equals | acc])
  defp tokenize(<<?(, rest::binary>>, acc), do: tokenize(rest, [:lparen | acc])
  defp tokenize(<<?), rest::binary>>, acc), do: tokenize(rest, [:rparen | acc])
  defp tokenize(<<?[, rest::binary>>, acc), do: tokenize(rest, [:lbracket | acc])
  defp tokenize(<<?], rest::binary>>, acc), do: tokenize(rest, [:rbracket | acc])
  defp tokenize(<<?{, rest::binary>>, acc), do: tokenize(rest, [:lbrace | acc])
  defp tokenize(<<?}, rest::binary>>, acc), do: tokenize(rest, [:rbrace | acc])
  defp tokenize(<<?,, rest::binary>>, acc), do: tokenize(rest, [:comma | acc])
  defp tokenize(<<?:, rest::binary>>, acc), do: tokenize(rest, [:colon | acc])

  defp tokenize(<<?", rest::binary>>, acc) do
    case read_string(rest, []) do
      {:ok, str, rest} -> tokenize(rest, [{:string, str} | acc])
      {:error, _} = err -> err
    end
  end

  defp tokenize(<<c, _::binary>> = input, acc) when c in ?0..?9 or c == ?- do
    {num, rest} = read_number(input)
    tokenize(rest, [{:number, num} | acc])
  end

  defp tokenize(<<c, _::binary>> = input, acc) when c in ?a..?z or c in ?A..?Z or c == ?_ do
    {word, rest} = read_word(input)

    token =
      case word do
        "true" -> true
        "false" -> false
        "null" -> :null
        _ -> {:identifier, word}
      end

    tokenize(rest, [token | acc])
  end

  defp tokenize(<<c, _::binary>>, _acc) do
    {:error, "unexpected character: #{<<c>>}"}
  end

  defp read_string("", _acc), do: {:error, "unterminated string"}

  defp read_string(<<?\\, ?", rest::binary>>, acc) do
    read_string(rest, ["\"" | acc])
  end

  defp read_string(<<?\\, ?n, rest::binary>>, acc) do
    read_string(rest, ["\n" | acc])
  end

  defp read_string(<<?\\, ?t, rest::binary>>, acc) do
    read_string(rest, ["\t" | acc])
  end

  defp read_string(<<?\\, ?\\, rest::binary>>, acc) do
    read_string(rest, ["\\" | acc])
  end

  defp read_string(<<?\\, c::utf8, rest::binary>>, acc) do
    read_string(rest, [<<c::utf8>> | acc])
  end

  defp read_string(<<?", rest::binary>>, acc) do
    {:ok, acc |> Enum.reverse() |> IO.chardata_to_string(), rest}
  end

  defp read_string(<<c::utf8, rest::binary>>, acc) do
    read_string(rest, [<<c::utf8>> | acc])
  end

  defp read_number(input) do
    {digits, rest} = read_while(input, &number_char?/1)

    num =
      if String.contains?(digits, ".") do
        {f, ""} = Float.parse(digits)
        f
      else
        {i, ""} = Integer.parse(digits)
        i
      end

    {num, rest}
  end

  defp number_char?(c), do: c in ?0..?9 or c == ?. or c == ?- or c == ?e or c == ?E or c == ?+

  defp read_word(input) do
    read_while(input, fn c ->
      c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_
    end)
  end

  defp read_while(input, pred) do
    do_read_while(input, pred, [])
  end

  defp do_read_while(<<c, rest::binary>>, pred, acc) do
    if pred.(c) do
      do_read_while(rest, pred, [c | acc])
    else
      {acc |> Enum.reverse() |> IO.chardata_to_string(), <<c, rest::binary>>}
    end
  end

  defp do_read_while("", _pred, acc) do
    {acc |> Enum.reverse() |> IO.chardata_to_string(), ""}
  end

  defp skip_line(""), do: {"", ""}
  defp skip_line(<<?\n, rest::binary>>), do: {"", rest}
  defp skip_line(<<_, rest::binary>>), do: skip_line(rest)
end
