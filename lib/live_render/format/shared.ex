defmodule LiveRender.Format.Shared do
  @moduledoc false

  # --- Streaming helpers ---

  @doc """
  Common stream_push logic: appends chunk, delegates to fence detection or
  format-specific `process_fence_buffer/2`.
  """
  def stream_push(state, chunk, process_fence_buffer) do
    buf = state.buffer <> chunk

    if state.in_fence do
      process_fence_buffer.(state, buf)
    else
      {fields, events} = detect_fence(state, buf)
      {Map.merge(state, fields), events}
    end
  end

  @doc "Detects ```spec fence opening in a buffer. Returns events and updated state fields."
  def detect_fence(state_fields, buf) do
    case String.split(buf, "```spec", parts: 2) do
      [before, rest] ->
        remainder = String.trim_leading(rest, "\n")
        events = if before != "", do: [{:text, before}], else: []
        {Map.merge(state_fields, %{in_fence: true, buffer: remainder}), events}

      [_] ->
        {passthrough, held} = hold_backticks(buf)
        events = if passthrough != "", do: [{:text, passthrough}], else: []
        {Map.put(state_fields, :buffer, held), events}
    end
  end

  @doc "Holds trailing backticks to avoid partial fence detection."
  def hold_backticks(buf) do
    if String.ends_with?(buf, "`") do
      idx = byte_size(buf) - count_trailing_backticks(buf)
      {binary_part(buf, 0, idx), binary_part(buf, idx, byte_size(buf) - idx)}
    else
      {buf, ""}
    end
  end

  @doc "Splits a buffer into complete lines and a remainder."
  def split_lines(buf) do
    parts = String.split(buf, "\n", parts: :infinity)
    {remainder, complete} = List.pop_at(parts, -1)
    {complete, remainder}
  end

  @doc """
  Extracts content from inside a code fence in a complete text.

  Tries each marker in order. Returns the content between the opening fence
  and the closing ``` (or end of string).
  """
  def extract_fence(text, markers \\ ["```spec"]) do
    Enum.find_value(markers, :none, &try_extract_marker(text, &1))
  end

  defp try_extract_marker(text, marker) do
    case String.split(text, marker <> "\n", parts: 2) do
      [_before, rest] -> {:ok, extract_fence_content(rest)}
      [_] -> nil
    end
  end

  defp extract_fence_content(rest) do
    case String.split(rest, "```", parts: 2) do
      [inner, _] -> String.trim(inner)
      [inner] -> String.trim(inner)
    end
  end

  defp count_trailing_backticks(buf) do
    buf
    |> String.reverse()
    |> then(&Regex.run(~r/\A`+/, &1))
    |> case do
      [m] -> byte_size(m)
      nil -> 0
    end
  end

  # --- Prompt helpers ---

  @doc "Builds the JSON-format prompt preamble with components, actions, rules."
  def json_prompt(format_section, component_map, actions, opts) do
    custom_rules = Keyword.get(opts, :custom_rules, [])

    """
    You generate UI specs as JSON. Use ONLY these components and actions.

    #{format_section}
    #{data_binding_section()}
    #{visibility_section()}
    ## Components

    #{components_section(component_map)}
    #{actions_section(actions)}#{rules_section(custom_rules)}\
    """
    |> String.trim()
  end

  @doc "Appends edit mode sections to a base prompt when current_spec is present."
  def with_edit_mode(base_prompt, opts, edit_section_fn) do
    current_spec = Keyword.get(opts, :current_spec)

    if current_spec && current_spec != %{} do
      current_json = Jason.encode!(current_spec, pretty: true)

      base_prompt <>
        "\n\n" <>
        edit_section_fn.() <>
        "\n\n" <>
        "CURRENT UI STATE (already loaded, DO NOT recreate existing elements):\n```\n#{current_json}\n```\n"
    else
      base_prompt
    end
  end

  @doc "Formats the components section of the system prompt."
  def components_section(component_map) do
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
  end

  @doc "Formats the actions section of the system prompt."
  def actions_section([]), do: ""

  def actions_section(actions) do
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

  @doc "Formats the custom rules section of the system prompt."
  def rules_section([]), do: ""

  def rules_section(custom_rules) do
    rules = Enum.map_join(custom_rules, "\n", &"- #{&1}")
    "\n## Rules\n\n#{rules}\n"
  end

  def data_binding_section do
    """
    ## Data binding

    Any prop value can reference the state model:
    - {"$state": "/path/to/value"} — read a value from state
    - {"$cond": {"$state": "/flag"}, "$then": "yes", "$else": "no"} — conditional
    - {"$cond": {"$state": "/val", "eq": "x"}, "$then": "matched", "$else": "other"} — equality check
    """
  end

  def visibility_section do
    """
    ## Visibility

    Elements can have a "visible" field with conditions:
    - "visible": {"$state": "/show_details"} — show when truthy
    - "visible": {"$state": "/status", "eq": "active"} — show when equal
    - "visible": [{"$state": "/a"}, {"$state": "/b"}] — show when all truthy
    """
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

  @doc "Builds the YAML-format prompt preamble with components, actions, rules."
  def yaml_prompt(format_section, edit_section, component_map, actions, opts) do
    custom_rules = Keyword.get(opts, :custom_rules, [])
    current_spec = Keyword.get(opts, :current_spec)

    edit_part =
      if current_spec && current_spec != %{} do
        current_yaml = serialize_spec_yaml(current_spec)

        "\n\n#{edit_section}\n\n" <>
          "CURRENT UI STATE (already loaded, DO NOT recreate existing elements):\n```\n#{current_yaml}\n```\n"
      else
        ""
      end

    """
    You generate UI specs as YAML. Use ONLY these components and actions.

    #{format_section}
    #{data_binding_section()}
    #{visibility_section()}
    ## Components

    #{components_section(component_map)}
    #{actions_section(actions)}#{edit_part}#{rules_section(custom_rules)}\
    """
    |> String.trim()
  end

  defp serialize_spec_yaml(spec) do
    spec
    |> yaml_serialize()
    |> String.trim()
  end

  defp yaml_serialize(data, indent \\ 0) do
    pad = String.duplicate("  ", indent)

    case data do
      map when is_map(map) and map_size(map) == 0 ->
        "{}"

      map when is_map(map) ->
        map
        |> Enum.sort_by(fn {k, _} -> k end)
        |> Enum.map_join("\n", &yaml_entry(&1, pad, indent))

      _ ->
        "#{pad}#{yaml_value(data)}"
    end
  end

  defp yaml_entry({k, nested}, pad, indent) when is_map(nested) and map_size(nested) > 0 do
    "#{pad}#{k}:\n#{yaml_serialize(nested, indent + 1)}"
  end

  defp yaml_entry({k, [_ | _] = list}, pad, _indent) do
    items = Enum.map_join(list, "\n", &"#{pad}  - #{yaml_value(&1)}")
    "#{pad}#{k}:\n#{items}"
  end

  defp yaml_entry({k, v}, pad, _indent) do
    "#{pad}#{k}: #{yaml_value(v)}"
  end

  defp yaml_value(nil), do: "null"
  defp yaml_value(true), do: "true"
  defp yaml_value(false), do: "false"
  defp yaml_value(v) when is_integer(v), do: Integer.to_string(v)
  defp yaml_value(v) when is_float(v), do: Float.to_string(v)
  defp yaml_value(v) when is_binary(v), do: inspect(v)
  defp yaml_value(list) when is_list(list), do: Jason.encode!(list)
  defp yaml_value(map) when is_map(map), do: Jason.encode!(map)
  defp yaml_value(v), do: inspect(v)

  defp format_type(%{"type" => "string", "enum" => values}) do
    Enum.join(values, " | ")
  end

  defp format_type(%{"type" => type}), do: type
  defp format_type(%{"anyOf" => types}), do: Enum.map_join(types, " | ", &format_type/1)
  defp format_type(_), do: "any"
end
