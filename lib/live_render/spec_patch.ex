defmodule LiveRender.SpecPatch do
  @moduledoc """
  Applies RFC 6902 JSON Patch operations to a LiveRender spec.

  Used for progressive streaming: the LLM outputs one patch operation per line
  inside a ```` ```spec ```` fence, and each patch is applied to build the spec
  incrementally.

  Supported operations: `add`, `replace`, `remove`.
  """

  @type spec :: %{String.t() => term()}
  @type patch :: %{String.t() => term()}

  @doc """
  Applies a single JSON Patch operation to a spec.

  ## Examples

      iex> spec = %{"elements" => %{}, "state" => %{}}
      iex> LiveRender.SpecPatch.apply(spec, %{"op" => "add", "path" => "/root", "value" => "main"})
      %{"elements" => %{}, "state" => %{}, "root" => "main"}
  """
  @spec apply(spec(), patch()) :: spec()
  def apply(spec, %{"op" => "add", "path" => path, "value" => value}) do
    set_path(spec, path, value)
  end

  def apply(spec, %{"op" => "replace", "path" => path, "value" => value}) do
    set_path(spec, path, value)
  end

  def apply(spec, %{"op" => "remove", "path" => path}) do
    remove_path(spec, path)
  end

  def apply(spec, _unknown), do: spec

  @doc """
  Parses a single JSONL line and applies it to the spec if valid.
  Returns `{:ok, updated_spec}` or `:skip` if the line isn't a valid patch.
  """
  @spec parse_and_apply(spec(), String.t()) :: {:ok, spec()} | :skip
  def parse_and_apply(spec, line) do
    trimmed = String.trim(line)

    if trimmed == "" or String.starts_with?(trimmed, "//") do
      :skip
    else
      case Jason.decode(trimmed) do
        {:ok, %{"op" => _, "path" => _} = patch} ->
          {:ok, __MODULE__.apply(spec, patch)}

        _ ->
          :skip
      end
    end
  end

  defp set_path(spec, "/" <> rest, value) do
    segments = String.split(rest, "/")
    deep_put(spec, segments, value)
  end

  defp set_path(spec, _invalid, _value), do: spec

  defp remove_path(spec, "/" <> rest) do
    segments = String.split(rest, "/")
    deep_remove(spec, segments)
  end

  defp remove_path(spec, _invalid), do: spec

  defp deep_put(map, [key], value) when is_map(map) do
    case integer_key?(key, map) do
      {:list, idx, list} -> Map.put(map, key, list_insert(list, idx, value))
      :map -> Map.put(map, key, value)
    end
  end

  defp deep_put(map, [key | rest], value) when is_map(map) do
    child = Map.get(map, key, %{})
    Map.put(map, key, deep_put(child, rest, value))
  end

  # RFC 6902: "-" means append to the end of an array
  defp deep_put(list, ["-"], value) when is_list(list) do
    list ++ [value]
  end

  # Numeric index on a list
  defp deep_put(list, [key], value) when is_list(list) do
    case Integer.parse(key) do
      {idx, ""} -> list_insert(list, idx, value)
      _ -> list
    end
  end

  # Recurse into list element by numeric index
  defp deep_put(list, [key | rest], value) when is_list(list) do
    case Integer.parse(key) do
      {idx, ""} when idx >= 0 and idx < length(list) ->
        List.update_at(list, idx, &deep_put(&1, rest, value))

      _ ->
        list
    end
  end

  defp deep_put(other, _keys, _value), do: other

  defp deep_remove(map, [key]) when is_map(map), do: Map.delete(map, key)

  defp deep_remove(map, [key | rest]) when is_map(map) do
    case Map.get(map, key) do
      nil -> map
      child -> Map.put(map, key, deep_remove(child, rest))
    end
  end

  defp deep_remove(other, _keys), do: other

  # Check if key looks like an array index being added to a list value
  defp integer_key?(key, parent) do
    case Integer.parse(key) do
      {idx, ""} ->
        # Check if the parent already holds a list at this numeric key's parent
        # This is for paths like /state/items/0 where items is a list
        # But our spec is map-based, so only convert if the existing value is a list
        existing = Map.get(parent, key)

        if is_list(existing) do
          {:list, idx, existing}
        else
          :map
        end

      _ ->
        :map
    end
  end

  defp list_insert(list, idx, value) when idx >= length(list) do
    list ++ [value]
  end

  defp list_insert(list, idx, value) do
    List.insert_at(list, idx, value)
  end
end
