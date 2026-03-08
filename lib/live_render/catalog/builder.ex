defmodule LiveRender.Catalog.Builder do
  @moduledoc false

  @doc """
  Builds a system prompt from component and action definitions.
  """
  @spec build(%{String.t() => module()}, [{atom(), String.t()}], keyword()) :: String.t()
  def build(component_map, actions, opts \\ []) do
    custom_rules = Keyword.get(opts, :custom_rules, [])

    components_section =
      component_map
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map_join("\n\n", fn {name, mod} ->
        meta = mod.__component_meta__()
        schema = mod.json_schema()
        props_doc = format_properties(schema)
        slots = meta.slots

        slots_doc =
          if slots == [] do
            ""
          else
            "\n  Slots: #{Enum.join(slots, ", ")}"
          end

        """
        ### #{name}
        #{meta.description}
        #{props_doc}#{slots_doc}\
        """
        |> String.trim()
      end)

    actions_section =
      if actions == [] do
        ""
      else
        action_docs =
          actions
          |> Enum.map_join("\n", fn {name, desc} ->
            "- #{name}: #{desc}"
          end)

        """

        ## Actions

        #{action_docs}

        Built-in actions:
        - set_state: Set a value at a state path. Params: {"path": "/state/key", "value": ...}
        """
      end

    rules_section =
      if custom_rules == [] do
        ""
      else
        rules = Enum.map_join(custom_rules, "\n", &"- #{&1}")
        "\n## Rules\n\n#{rules}\n"
      end

    mode = Keyword.get(opts, :mode, :object)

    format_section =
      case mode do
        :patch ->
          """
          ## Spec format (JSONL, RFC 6902 JSON Patch)

          Output JSONL patch operations inside a ```spec fence — one JSON object per line.
          Each line is a patch: {"op":"add","path":"/...","value":...}

          Start with /root, then interleave /elements and /state patches so the UI fills in
          progressively as it streams. Output state patches right after the elements that use them.

          Example (each line is a separate JSON object):
          ```spec
          {"op":"add","path":"/root","value":"main"}
          {"op":"add","path":"/elements/main","value":{"type":"stack","props":{},"children":["heading","card-1"]}}
          {"op":"add","path":"/elements/heading","value":{"type":"heading","props":{"text":"Dashboard"},"children":[]}}
          {"op":"add","path":"/elements/card-1","value":{"type":"card","props":{"title":"Stats"},"children":["metric-1"]}}
          {"op":"add","path":"/elements/metric-1","value":{"type":"metric","props":{"label":"Users","value":{"$state":"/users"}},"children":[]}}
          {"op":"add","path":"/state/users","value":"1,234"}
          ```

          For state arrays, stream one item at a time:
          {"op":"add","path":"/state/items","value":[]}
          {"op":"add","path":"/state/items/-","value":{"id":"1","name":"First"}}
          {"op":"add","path":"/state/items/-","value":{"id":"2","name":"Second"}}

          Supported ops: add, replace, remove.
          """

        :object ->
          """
          ## Spec format

          Output a JSON object with:
          - "root": string ID of the root element
          - "state": object with initial state values (optional)
          - "elements": object mapping element IDs to element definitions

          Each element: {"type": "component_name", "props": {...}, "children": ["child-id", ...]}
          """
      end

    """
    You generate UI specs as JSON. Use ONLY these components and actions.

    #{format_section}
    ## Data binding

    Any prop value can reference the state model:
    - {"$state": "/path/to/value"} — read a value from state
    - {"$cond": {"$state": "/flag"}, "$then": "yes", "$else": "no"} — conditional
    - {"$cond": {"$state": "/val", "eq": "x"}, "$then": "matched", "$else": "other"} — equality check

    ## Visibility

    Elements can have a "visible" field with conditions:
    - "visible": {"$state": "/show_details"} — show when truthy
    - "visible": {"$state": "/status", "eq": "active"} — show when equal
    - "visible": [{"$state": "/a"}, {"$state": "/b"}] — show when all truthy

    ## Components

    #{components_section}
    #{actions_section}#{rules_section}\
    """
    |> String.trim()
  end

  @doc """
  Builds a JSON Schema describing the full spec format.
  """
  @spec spec_json_schema(%{String.t() => module()}) :: map()
  def spec_json_schema(component_map) do
    type_enum = Map.keys(component_map)

    %{
      "type" => "object",
      "properties" => %{
        "root" => %{"type" => "string"},
        "state" => %{"type" => "object"},
        "elements" => %{
          "type" => "object",
          "additionalProperties" => %{
            "type" => "object",
            "properties" => %{
              "type" => %{"type" => "string", "enum" => type_enum},
              "props" => %{"type" => "object"},
              "children" => %{"type" => "array", "items" => %{"type" => "string"}},
              "visible" => %{},
              "on" => %{"type" => "object"}
            },
            "required" => ["type", "props", "children"]
          }
        }
      },
      "required" => ["root", "elements"]
    }
  end

  defp format_properties(%{"properties" => properties} = schema) do
    required = Map.get(schema, "required", [])

    properties
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.map_join("\n", fn {name, prop} ->
      type = format_type(prop)
      req = if name in required, do: " (required)", else: ""
      desc = if prop["description"], do: " — #{prop["description"]}", else: ""
      "  - #{name}: #{type}#{req}#{desc}"
    end)
  end

  defp format_properties(_), do: "  (no props)"

  defp format_type(%{"type" => "string", "enum" => values}) do
    Enum.join(values, " | ")
  end

  defp format_type(%{"type" => type}), do: type
  defp format_type(%{"anyOf" => types}), do: Enum.map_join(types, " | ", &format_type/1)
  defp format_type(_), do: "any"
end
