defmodule LiveRender.StateResolver do
  @moduledoc """
  Resolves data binding expressions in component props against the spec state model.

  Expressions:
  - `{"$state": "/path/to/value"}` — read from state
  - `{"$bindState": "/path"}` — two-way binding (read value, renderer generates phx-change)
  - `{"$cond": ..., "$then": ..., "$else": ...}` — conditional prop values
  - `{"$template": "Hello, ${/user/name}!"}` — string interpolation
  - `{"$concat": ["Humidity: ", {"$state": "/humidity"}, "%"]}` — concatenate resolved parts into a string
  """

  @doc """
  Resolves all expressions in a value against the state map.

  Returns `{resolved_value, bindings}` where bindings is a map of prop keys
  that use `$bindState` and their state paths.
  """
  @spec resolve(term(), map()) :: term()
  def resolve(value, state) do
    do_resolve(value, state)
  end

  @doc """
  Extracts `$bindState` paths from props. Returns a map of `%{prop_key => state_path}`.
  """
  @spec extract_bindings(map()) :: %{String.t() => String.t()}
  def extract_bindings(props) when is_map(props) do
    Enum.reduce(props, %{}, fn
      {key, %{"$bindState" => path}}, acc -> Map.put(acc, key, path)
      _, acc -> acc
    end)
  end

  def extract_bindings(_), do: %{}

  @doc """
  Gets a value from a state map using a JSON Pointer path.

      iex> LiveRender.StateResolver.get_in_path(%{"weather" => %{"temp" => 72}}, "/weather/temp")
      72
  """
  @spec get_in_path(map(), String.t()) :: term()
  def get_in_path(state, path) when is_binary(path) do
    keys = split_path(path)
    get_in_nested(state, keys)
  end

  def get_in_path(_state, _path), do: nil

  @doc """
  Sets a value in a state map at a JSON Pointer path.
  """
  @spec put_in_path(map(), String.t(), term()) :: map()
  def put_in_path(state, path, value) when is_binary(path) do
    keys = split_path(path)
    put_in_nested(state, keys, value)
  end

  def put_in_path(state, _path, _value), do: state

  # --- Resolution ---

  defp do_resolve(%{"$state" => path}, state) do
    get_in_path(state, path)
  end

  defp do_resolve(%{"$bindState" => path}, state) do
    get_in_path(state, path)
  end

  defp do_resolve(%{"$cond" => condition, "$then" => then_val, "$else" => else_val}, state) do
    if evaluate_condition(condition, state) do
      do_resolve(then_val, state)
    else
      do_resolve(else_val, state)
    end
  end

  defp do_resolve(%{"$cond" => condition, "$then" => then_val}, state) do
    if evaluate_condition(condition, state), do: do_resolve(then_val, state)
  end

  defp do_resolve(%{"$concat" => parts}, state) when is_list(parts) do
    parts
    |> Enum.map(&do_resolve(&1, state))
    |> Enum.map_join(&to_string/1)
  end

  defp do_resolve(%{"$template" => template}, state) do
    Regex.replace(~r/\$\{([^}]+)\}/, template, fn _match, path ->
      case get_in_path(state, path) do
        nil -> ""
        val -> to_string(val)
      end
    end)
  end

  defp do_resolve(map, state) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, do_resolve(v, state)} end)
  end

  defp do_resolve(list, state) when is_list(list) do
    Enum.map(list, &do_resolve(&1, state))
  end

  defp do_resolve(value, _state), do: value

  # --- Condition evaluation ---

  defp evaluate_condition(%{"$state" => path} = cond_map, state) do
    value = get_in_path(state, path)

    case Map.get(cond_map, "eq") do
      nil -> !!value
      expected -> value == expected
    end
  end

  defp evaluate_condition(value, _state), do: !!value

  # --- Nested access ---

  defp get_in_nested(value, []), do: value

  defp get_in_nested(map, [key | rest]) when is_map(map) do
    val = Map.get(map, key) || Map.get(map, String.to_existing_atom(key))
    get_in_nested(val, rest)
  rescue
    ArgumentError -> nil
  end

  defp get_in_nested(_, _), do: nil

  defp put_in_nested(map, [key], value) when is_map(map) do
    Map.put(map, key, value)
  end

  defp put_in_nested(map, [key | rest], value) when is_map(map) do
    child = Map.get(map, key, %{})
    Map.put(map, key, put_in_nested(child, rest, value))
  end

  defp put_in_nested(_, [key | rest], value) do
    %{key => put_in_nested(%{}, rest, value)}
  end

  defp split_path(path) do
    path
    |> String.split("/")
    |> Enum.reject(&(&1 == ""))
  end
end
