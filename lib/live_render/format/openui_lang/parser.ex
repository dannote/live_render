defmodule LiveRender.Format.OpenUILang.Parser do
  @moduledoc false

  alias LiveRender.Format.OpenUILang.Tokenizer

  @type ast_node ::
          {:assign, String.t(), ast_node()}
          | {:component, String.t(), [ast_node()]}
          | {:ref, String.t()}
          | {:string, String.t()}
          | {:number, number()}
          | {:boolean, boolean()}
          | :null
          | {:array, [ast_node()]}
          | {:object, [{String.t(), ast_node()}]}

  @doc """
  Parses OpenUI Lang source text into a list of assignment AST nodes.
  """
  @spec parse(String.t()) :: {:ok, [ast_node()]} | {:error, String.t()}
  def parse(text) do
    with {:ok, tokens} <- Tokenizer.tokenize(text) do
      tokens = strip_leading_newlines(tokens)
      parse_statements(tokens, [])
    end
  end

  @doc """
  Parses a single line of OpenUI Lang into an assignment AST node.
  """
  @spec parse_line(String.t()) :: {:ok, ast_node() | nil} | {:error, String.t()}
  def parse_line(text) do
    with {:ok, tokens} <- Tokenizer.tokenize(text) do
      tokens
      |> Enum.reject(&(&1 == :newline))
      |> parse_line_tokens()
    end
  end

  defp parse_line_tokens([]), do: {:ok, nil}

  defp parse_line_tokens(tokens) do
    case parse_assignment(tokens) do
      {:ok, node, _rest} -> {:ok, node}
      {:error, _} = err -> err
    end
  end

  defp parse_statements([], acc), do: {:ok, Enum.reverse(acc)}

  defp parse_statements([:newline | rest], acc) do
    parse_statements(rest, acc)
  end

  defp parse_statements(tokens, acc) do
    case parse_assignment(tokens) do
      {:ok, node, rest} ->
        rest = skip_newlines(rest)
        parse_statements(rest, [node | acc])

      {:error, _} = err ->
        err
    end
  end

  defp parse_assignment([{:identifier, name}, :equals | rest]) do
    case parse_expression(rest) do
      {:ok, expr, rest} -> {:ok, {:assign, name, expr}, rest}
      {:error, _} = err -> err
    end
  end

  defp parse_assignment(tokens) do
    {:error, "expected assignment (identifier = expression), got: #{inspect_tokens(tokens)}"}
  end

  defp parse_expression([{:identifier, name}, :lparen | rest]) do
    if uppercase?(name) do
      parse_component_args(rest, [], name)
    else
      {:error, "expected component name to start with uppercase, got: #{name}"}
    end
  end

  defp parse_expression([{:string, val} | rest]), do: {:ok, {:string, val}, rest}
  defp parse_expression([{:number, val} | rest]), do: {:ok, {:number, val}, rest}
  defp parse_expression([true | rest]), do: {:ok, {:boolean, true}, rest}
  defp parse_expression([false | rest]), do: {:ok, {:boolean, false}, rest}
  defp parse_expression([:null | rest]), do: {:ok, :null, rest}
  defp parse_expression([:lbracket | rest]), do: parse_array(rest, [])
  defp parse_expression([:lbrace | rest]), do: parse_object(rest, [])

  defp parse_expression([{:identifier, name} | rest]) do
    {:ok, {:ref, name}, rest}
  end

  defp parse_expression(tokens) do
    {:error, "unexpected token in expression: #{inspect_tokens(tokens)}"}
  end

  defp parse_component_args([:rparen | rest], acc, name) do
    {:ok, {:component, name, Enum.reverse(acc)}, rest}
  end

  defp parse_component_args(tokens, acc, name) do
    tokens = skip_commas_and_newlines(tokens)

    case tokens do
      [:rparen | rest] ->
        {:ok, {:component, name, Enum.reverse(acc)}, rest}

      _ ->
        case parse_expression(tokens) do
          {:ok, expr, rest} ->
            rest = skip_commas_and_newlines(rest)
            parse_component_args(rest, [expr | acc], name)

          {:error, _} = err ->
            err
        end
    end
  end

  defp parse_array([:rbracket | rest], acc) do
    {:ok, {:array, Enum.reverse(acc)}, rest}
  end

  defp parse_array(tokens, acc) do
    tokens = skip_commas_and_newlines(tokens)

    case tokens do
      [:rbracket | rest] ->
        {:ok, {:array, Enum.reverse(acc)}, rest}

      _ ->
        case parse_expression(tokens) do
          {:ok, expr, rest} ->
            rest = skip_commas_and_newlines(rest)
            parse_array(rest, [expr | acc])

          {:error, _} = err ->
            err
        end
    end
  end

  defp parse_object([:rbrace | rest], acc) do
    {:ok, {:object, Enum.reverse(acc)}, rest}
  end

  defp parse_object(tokens, acc) do
    tokens = skip_commas_and_newlines(tokens)

    case tokens do
      [:rbrace | rest] ->
        {:ok, {:object, Enum.reverse(acc)}, rest}

      [{:identifier, key}, :colon | rest] ->
        case parse_expression(rest) do
          {:ok, val, rest} ->
            rest = skip_commas_and_newlines(rest)
            parse_object(rest, [{key, val} | acc])

          {:error, _} = err ->
            err
        end

      [{:string, key}, :colon | rest] ->
        case parse_expression(rest) do
          {:ok, val, rest} ->
            rest = skip_commas_and_newlines(rest)
            parse_object(rest, [{key, val} | acc])

          {:error, _} = err ->
            err
        end

      _ ->
        {:error, "expected object key, got: #{inspect_tokens(tokens)}"}
    end
  end

  defp uppercase?(<<c, _::binary>>) when c in ?A..?Z, do: true
  defp uppercase?(_), do: false

  defp skip_newlines([:newline | rest]), do: skip_newlines(rest)
  defp skip_newlines(tokens), do: tokens

  defp skip_commas_and_newlines([:comma | rest]), do: skip_commas_and_newlines(rest)
  defp skip_commas_and_newlines([:newline | rest]), do: skip_commas_and_newlines(rest)
  defp skip_commas_and_newlines(tokens), do: tokens

  defp strip_leading_newlines([:newline | rest]), do: strip_leading_newlines(rest)
  defp strip_leading_newlines(tokens), do: tokens

  defp inspect_tokens([]), do: "end of input"
  defp inspect_tokens(tokens), do: tokens |> Enum.take(3) |> inspect()
end
