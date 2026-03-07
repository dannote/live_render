defmodule LiveRender.SchemaAdapter do
  @moduledoc """
  Converts component schemas to JSON Schema and validates props.

  Supports three schema formats:

  - **JSONSpec** — Elixir typespec maps that are already JSON Schema (pass through)
  - **NimbleOptions** — keyword list schemas converted to JSON Schema
  - **Raw JSON Schema** — plain maps with `"type"` keys (pass through)
  """

  @doc """
  Converts a schema to JSON Schema map.

  Detects the format automatically:

  - Maps with string keys and `"type"` → already JSON Schema, pass through
  - Keyword lists → NimbleOptions, convert
  - Other maps → assumed JSONSpec output, pass through
  """
  @spec to_json_schema(term()) :: map()
  def to_json_schema(schema) when is_map(schema), do: schema
  def to_json_schema(schema) when is_list(schema), do: nimble_to_json_schema(schema)
  def to_json_schema(_), do: %{}

  @doc """
  Validates props against a schema. Returns validated props with defaults applied.
  """
  @spec validate(term(), map()) :: {:ok, map()} | {:error, term()}
  def validate(schema, props) when is_list(schema) do
    validate_nimble(schema, props)
  end

  def validate(schema, props) when is_map(schema) do
    validate_json_schema(schema, props)
  end

  def validate(_, props), do: {:ok, props}

  # --- NimbleOptions → JSON Schema ---

  defp nimble_to_json_schema(opts) when is_list(opts) do
    {properties, required} =
      Enum.reduce(opts, {%{}, []}, fn {key, spec}, {props, req} ->
        prop = nimble_type_to_json(spec[:type])
        prop = if spec[:doc], do: Map.put(prop, "description", spec[:doc]), else: prop

        req = if spec[:required], do: [to_string(key) | req], else: req
        {Map.put(props, to_string(key), prop), req}
      end)

    schema = %{
      "type" => "object",
      "properties" => properties,
      "additionalProperties" => false
    }

    if required == [], do: schema, else: Map.put(schema, "required", Enum.reverse(required))
  end

  defp nimble_type_to_json(nil), do: %{}
  defp nimble_type_to_json(:string), do: %{"type" => "string"}
  defp nimble_type_to_json(:integer), do: %{"type" => "integer"}
  defp nimble_type_to_json(:float), do: %{"type" => "number"}
  defp nimble_type_to_json(:number), do: %{"type" => "number"}
  defp nimble_type_to_json(:boolean), do: %{"type" => "boolean"}
  defp nimble_type_to_json(:atom), do: %{"type" => "string"}
  defp nimble_type_to_json(:any), do: %{}
  defp nimble_type_to_json(:map), do: %{"type" => "object"}

  defp nimble_type_to_json({:in, values}) do
    %{"type" => "string", "enum" => Enum.map(values, &to_string/1)}
  end

  defp nimble_type_to_json({:list, inner}) do
    %{"type" => "array", "items" => nimble_type_to_json(inner)}
  end

  defp nimble_type_to_json({:or, types}) do
    %{"anyOf" => Enum.map(types, &nimble_type_to_json/1)}
  end

  defp nimble_type_to_json({:keyword_list, inner}) do
    nimble_to_json_schema(inner)
  end

  defp nimble_type_to_json(_), do: %{}

  # --- NimbleOptions validation ---

  defp validate_nimble(schema, props) do
    keyword_props =
      Enum.reduce(schema, [], fn {key, spec}, acc ->
        str_key = to_string(key)

        value =
          case {Map.get(props, str_key), Map.get(props, key)} do
            {nil, nil} -> spec[:default]
            {nil, v} -> v
            {v, _} -> coerce_value(v, spec[:type])
          end

        if is_nil(value) and not Keyword.get(spec, :required, false) do
          acc
        else
          [{key, value} | acc]
        end
      end)
      |> Enum.reverse()

    if Code.ensure_loaded?(NimbleOptions) do
      case NimbleOptions.validate(keyword_props, schema) do
        {:ok, validated} ->
          result = Map.new(validated)
          {:ok, apply_defaults(result, schema)}

        {:error, %NimbleOptions.ValidationError{} = err} ->
          {:error, Exception.message(err)}
      end
    else
      {:ok, apply_defaults(Map.new(keyword_props), schema)}
    end
  end

  defp apply_defaults(props, schema) do
    Enum.reduce(schema, props, fn {key, spec}, acc ->
      if Map.has_key?(acc, key) do
        acc
      else
        Map.put(acc, key, spec[:default])
      end
    end)
  end

  defp coerce_value(value, {:in, allowed}) when is_binary(value) do
    atom_value = String.to_existing_atom(value)
    if atom_value in allowed, do: atom_value, else: value
  rescue
    ArgumentError -> value
  end

  defp coerce_value(value, _), do: value

  # --- JSON Schema validation (lightweight — checks required + types) ---

  defp validate_json_schema(schema, props) do
    required = Map.get(schema, "required", [])

    missing = Enum.filter(required, &(not Map.has_key?(props, &1)))

    if missing != [] do
      {:error, "missing required properties: #{Enum.join(missing, ", ")}"}
    else
      {:ok, resolve_properties(schema, props)}
    end
  end

  defp resolve_properties(schema, props) do
    properties = Map.get(schema, "properties", %{})

    Map.new(properties, fn {key, _} -> {String.to_atom(key), Map.get(props, key)} end)
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end
end
