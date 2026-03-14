defmodule LiveRender.Format.OpenUILang do
  @moduledoc """
  Compact line-oriented DSL format, ~50% fewer tokens than JSON.

  The LLM outputs OpenUI Lang inside a `` ```spec `` fence:

      ```spec
      root = Stack([title, card1])
      title = Heading("Dashboard")
      card1 = Card([metric1], "Stats")
      metric1 = Metric("Users", "1,234")
      ```

  Each line `identifier = Expression` is parsed and compiled into a LiveRender spec map.
  """

  @behaviour LiveRender.Format

  alias LiveRender.Format.OpenUILang.Compiler
  alias LiveRender.Format.Shared

  @impl true
  def prompt(component_map, actions, opts) do
    custom_rules = Keyword.get(opts, :custom_rules, [])

    """
    You generate UI using OpenUI Lang. Use ONLY these components and actions.

    #{format_section()}
    #{signatures_section(component_map)}
    #{Shared.actions_section(actions)}#{Shared.rules_section(custom_rules)}\
    """
    |> String.trim()
  end

  @impl true
  def parse(text, opts \\ []) do
    catalog = catalog_from_opts(opts)

    case extract_fence(text) do
      {:ok, content} -> parse_and_compile(content, catalog)
      :none -> try_raw_parse(text, catalog)
    end
  end

  @impl true
  def stream_init(opts \\ []) do
    %{
      buffer: "",
      in_fence: false,
      lines_acc: [],
      catalog: catalog_from_opts(opts)
    }
  end

  @impl true
  def stream_push(state, chunk) do
    Shared.stream_push(state, chunk, &process_fence_buffer/2)
  end

  @impl true
  def stream_flush(state) do
    if state.in_fence and state.buffer != "" do
      buf = state.buffer <> "\n"
      {lines, _} = Shared.split_lines(buf)
      lines_acc = state.lines_acc ++ lines
      events = recompile(lines_acc, state.catalog)
      {%{state | buffer: "", in_fence: false, lines_acc: lines_acc}, events}
    else
      {state, []}
    end
  end

  # --- Fence processing ---

  defp process_fence_buffer(state, buf) do
    {lines, remainder} = Shared.split_lines(buf)

    {fence_closed, spec_lines} =
      Enum.reduce(lines, {false, []}, fn line, {closed, spec} ->
        if closed or String.trim(line) == "```" do
          {true, spec}
        else
          {false, spec ++ [line]}
        end
      end)

    lines_acc = state.lines_acc ++ spec_lines
    events = recompile(lines_acc, state.catalog)

    state = %{state | buffer: remainder, lines_acc: lines_acc}
    state = if fence_closed, do: %{state | in_fence: false}, else: state

    {state, events}
  end

  defp recompile(lines, catalog) do
    source = Enum.join(lines, "\n")

    case parse_and_compile(source, catalog) do
      {:ok, spec} when spec != %{} -> [{:spec, spec}]
      _ -> []
    end
  end

  # --- Parsing ---

  defp extract_fence(text) do
    Shared.extract_fence(text)
  end

  defp parse_and_compile(source, component_map) do
    alias LiveRender.Format.OpenUILang.Parser

    case Parser.parse(source) do
      {:ok, []} -> {:ok, %{}}
      {:ok, assignments} -> {:ok, Compiler.compile(assignments, component_map)}
      {:error, _reason} -> {:ok, %{}}
    end
  end

  defp try_raw_parse(text, catalog) do
    trimmed = String.trim(text)

    if trimmed != "" and not String.starts_with?(trimmed, "{") do
      parse_and_compile(trimmed, catalog)
    else
      {:ok, %{}}
    end
  end

  defp catalog_from_opts(opts) do
    case Keyword.get(opts, :catalog) do
      nil -> %{}
      mod when is_atom(mod) -> mod.components()
      map when is_map(map) -> map
    end
  end

  # --- Prompt generation ---

  defp format_section do
    """
    ## Output format (OpenUI Lang)

    Output a line-oriented spec inside a ```spec fence — one assignment per line.
    The first statement MUST assign to `root`.

    Syntax:
    - Assignment: `identifier = Expression`
    - Component call: `TypeName(arg1, arg2, ...)` — positional args
    - String: `"text"`
    - Number: `42`, `3.14`, `-1`
    - Boolean: `true` / `false`
    - Null: `null`
    - Array: `[a, b, c]`
    - Object: `{key: value}`
    - Reference: `identifier` — refers to another assignment

    Rules:
    - First statement must be the root (entry point)
    - Arguments are positional, based on the component signature below
    - Optional args can be omitted from the end
    - Forward references are allowed (use an identifier before defining it)
    - Write top-down: layout first, then content, then data
    - Use short, descriptive identifiers (e.g., `statsCard`, `tempMetric`)

    Example:
    ```spec
    root = Stack([heading, grid1])
    heading = Heading("Weather Dashboard")
    grid1 = Grid([nyCard, londonCard], 2)
    nyCard = Card([nyTemp, nyWind], "New York")
    nyTemp = Metric("Temperature", "72°F")
    nyWind = Metric("Wind", "8 mph")
    londonCard = Card([londonTemp], "London")
    londonTemp = Metric("Temperature", "15°C")
    ```
    """
  end

  defp signatures_section(component_map) do
    signatures =
      component_map
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map_join("\n", &format_signature/1)

    """
    ## Component signatures

    #{signatures}
    """
  end

  defp format_signature({_snake, mod}) do
    meta = mod.__component_meta__()
    pascal = Compiler.to_pascal_case(meta.name)
    schema = mod.json_schema()
    required = Map.get(schema, "required", [])
    properties = Map.get(schema, "properties", %{})

    args =
      Enum.map(meta.prop_order, fn key ->
        str_key = to_string(key)
        optional? = str_key not in required and key != :children
        type_hint = format_arg_type(Map.get(properties, str_key))
        suffix = if optional?, do: "?", else: ""
        "#{key}#{suffix}#{type_hint}"
      end)

    desc = if meta.description != "", do: " — #{meta.description}", else: ""
    "- `#{pascal}(#{Enum.join(args, ", ")})`#{desc}"
  end

  defp format_arg_type(%{"enum" => values}) do
    ": " <> Enum.map_join(values, "|", &inspect/1)
  end

  defp format_arg_type(%{"type" => "array"}), do: ": array"
  defp format_arg_type(%{"type" => "integer"}), do: ": int"
  defp format_arg_type(%{"type" => "number"}), do: ": number"
  defp format_arg_type(%{"type" => "boolean"}), do: ": bool"
  defp format_arg_type(_), do: ""
end
