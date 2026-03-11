defmodule LiveRender.Format.OpenUILang.Compiler do
  @moduledoc false

  alias LiveRender.Format.OpenUILang.Parser

  @doc """
  Compiles a list of AST assignment nodes into a LiveRender spec map.

  The catalog is used for:
  - Mapping PascalCase component names to snake_case type names
  - Mapping positional args to named props via prop_order
  """
  @spec compile([Parser.ast_node()], %{String.t() => module()}) :: map()
  def compile(assignments, component_map) do
    name_map = build_name_map(component_map)

    {root_id, elements} =
      assignments
      |> Enum.with_index()
      |> Enum.reduce({nil, %{}}, fn {{:assign, id, expr}, idx}, {root, elems} ->
        root = if idx == 0, do: id, else: root

        case compile_node(expr, name_map, component_map) do
          {:element, element} ->
            {root, Map.put(elems, id, element)}

          {:value, _value} ->
            {root, elems}
        end
      end)

    spec = %{"root" => root_id, "elements" => elements}

    state = extract_state(assignments, name_map, component_map)
    if state == %{}, do: spec, else: Map.put(spec, "state", state)
  end

  defp compile_node({:component, type_name, args}, name_map, component_map) do
    snake_name = Map.get(name_map, type_name, to_snake_case(type_name))
    mod = Map.get(component_map, snake_name)

    if mod do
      meta = mod.__component_meta__()
      prop_order = meta.prop_order

      {props, children} = map_positional_args(args, prop_order, meta.slots)

      resolved_props =
        Map.new(props, fn {key, val} ->
          {to_string(key), resolve_value(val) |> stringify_for_spec()}
        end)

      resolved_children =
        Enum.flat_map(children, fn
          {:ref, ref_id} -> [ref_id]
          {:array, items} -> Enum.map(items, &extract_ref_id/1)
          _ -> []
        end)

      element = %{
        "type" => snake_name,
        "props" => resolved_props,
        "children" => resolved_children
      }

      {:element, element}
    else
      {:element,
       %{
         "type" => snake_name,
         "props" => %{},
         "children" => []
       }}
    end
  end

  defp compile_node(expr, _name_map, _component_map) do
    {:value, resolve_value(expr)}
  end

  defp map_positional_args(args, prop_order, slots) do
    if :inner_block in slots do
      map_args_with_children(args, prop_order)
    else
      {zip_props(args, prop_order), []}
    end
  end

  defp map_args_with_children(args, [:children | prop_keys]) do
    case args do
      [first | rest] -> {zip_props(rest, prop_keys), [first]}
      [] -> {[], []}
    end
  end

  defp map_args_with_children(args, prop_keys) do
    {zip_props(args, prop_keys), []}
  end

  defp zip_props(args, keys) do
    Enum.zip(keys, args)
  end

  defp resolve_value({:string, val}), do: val
  defp resolve_value({:number, val}), do: val
  defp resolve_value({:boolean, val}), do: val
  defp resolve_value(:null), do: nil
  defp resolve_value({:ref, _id}), do: nil

  defp resolve_value({:array, items}) do
    Enum.map(items, &resolve_value/1)
  end

  defp resolve_value({:object, pairs}) do
    Map.new(pairs, fn {k, v} -> {k, resolve_value(v)} end)
  end

  defp resolve_value({:component, _name, _args}), do: nil

  defp extract_ref_id({:ref, id}), do: id
  defp extract_ref_id(_), do: nil

  # JSON specs use string keys and string/number/boolean/null/list/map values.
  # Numbers and booleans pass through; everything else stays as-is.
  # This ensures NimbleOptions coercion (string → atom for :in types) works
  # the same way as it does for JSON-sourced specs.
  defp stringify_for_spec(val) when is_number(val), do: val
  defp stringify_for_spec(val) when is_boolean(val), do: val
  defp stringify_for_spec(nil), do: nil
  defp stringify_for_spec(val) when is_binary(val), do: val
  defp stringify_for_spec(val) when is_list(val), do: Enum.map(val, &stringify_for_spec/1)

  defp stringify_for_spec(val) when is_map(val) do
    Map.new(val, fn {k, v} -> {to_string(k), stringify_for_spec(v)} end)
  end

  defp stringify_for_spec(val), do: val

  defp extract_state(_assignments, _name_map, _component_map), do: %{}

  defp build_name_map(component_map) do
    for {snake_name, _mod} <- component_map, into: %{} do
      pascal = to_pascal_case(snake_name)
      {pascal, snake_name}
    end
  end

  @doc "Converts PascalCase to snake_case."
  def to_snake_case(pascal) do
    pascal
    |> String.replace(~r/([A-Z])/, "_\\1")
    |> String.downcase()
    |> String.trim_leading("_")
  end

  @doc "Converts snake_case to PascalCase."
  def to_pascal_case(snake) do
    snake
    |> String.split("_")
    |> Enum.map_join(&String.capitalize/1)
  end
end
