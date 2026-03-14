defmodule LiveRender.SpecMerge do
  @moduledoc """
  RFC 7396 JSON Merge Patch for LiveRender specs.

  Deep-merges a patch into a base map:
  - `nil` values in patch delete the corresponding key from base
  - Arrays in patch replace (not concat) the array in base
  - Plain maps recurse
  - All other values replace
  """

  @doc """
  Deep-merges `patch` into `base`, returning a new map.

  Neither `base` nor `patch` is mutated.

  ## Examples

      iex> LiveRender.SpecMerge.merge(%{"a" => 1, "b" => 2}, %{"b" => 3, "c" => 4})
      %{"a" => 1, "b" => 3, "c" => 4}

      iex> LiveRender.SpecMerge.merge(%{"a" => 1, "b" => 2}, %{"b" => nil})
      %{"a" => 1}

      iex> LiveRender.SpecMerge.merge(
      ...>   %{"elements" => %{"card" => %{"props" => %{"title" => "Old"}}}},
      ...>   %{"elements" => %{"card" => %{"props" => %{"title" => "New"}}}}
      ...> )
      %{"elements" => %{"card" => %{"props" => %{"title" => "New"}}}}
  """
  @spec merge(map(), map()) :: map()
  def merge(base, patch) when is_map(base) and is_map(patch) do
    Enum.reduce(patch, base, &apply_key/2)
  end

  defp apply_key({key, nil}, acc), do: Map.delete(acc, key)

  defp apply_key({key, patch_map}, acc) when is_map(patch_map) do
    case Map.get(acc, key) do
      base_val when is_map(base_val) -> Map.put(acc, key, merge(base_val, patch_map))
      _ -> Map.put(acc, key, patch_map)
    end
  end

  defp apply_key({key, val}, acc), do: Map.put(acc, key, val)
end
