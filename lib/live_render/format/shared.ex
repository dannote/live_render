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

  defp format_type(%{"type" => "string", "enum" => values}) do
    Enum.join(values, " | ")
  end

  defp format_type(%{"type" => type}), do: type
  defp format_type(%{"anyOf" => types}), do: Enum.map_join(types, " | ", &format_type/1)
  defp format_type(_), do: "any"
end
