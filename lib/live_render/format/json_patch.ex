defmodule LiveRender.Format.JSONPatch do
  @moduledoc """
  JSONL RFC 6902 patch format for progressive streaming.

  The LLM outputs one JSON patch operation per line inside a `` ```spec `` fence.
  Each line adds or modifies a part of the spec, so the UI fills in progressively.
  """

  @behaviour LiveRender.Format

  alias LiveRender.Format.Shared

  @impl true
  def prompt(component_map, actions, opts) do
    Shared.json_prompt(format_section(), component_map, actions, opts)
  end

  @impl true
  def parse(text, _opts \\ []) do
    case extract_fence(text) do
      {:ok, content} -> parse_jsonl(content)
      :none -> try_raw_json(text)
    end
  end

  @impl true
  def stream_init(_opts \\ []) do
    %{
      buffer: "",
      in_fence: false,
      spec: %{"root" => nil, "elements" => %{}, "state" => %{}}
    }
  end

  @impl true
  def stream_push(state, chunk) do
    Shared.stream_push(state, chunk, &process_fence_buffer/2)
  end

  @impl true
  def stream_flush(state) do
    if state.in_fence and state.buffer != "" do
      {lines, _remainder} = Shared.split_lines(state.buffer <> "\n")
      {state, events} = process_lines(state, lines)
      {%{state | buffer: "", in_fence: false}, events}
    else
      {state, []}
    end
  end

  # --- Fence processing ---

  defp process_fence_buffer(state, buf) do
    {lines, remainder} = Shared.split_lines(buf)
    {state, events} = process_lines(%{state | buffer: ""}, lines)
    {%{state | buffer: remainder}, events}
  end

  defp process_lines(state, lines) do
    Enum.reduce(lines, {state, []}, fn line, {st, evts} ->
      process_single_line(st, evts, String.trim(line))
    end)
  end

  defp process_single_line(state, events, "```") do
    {%{state | in_fence: false}, events}
  end

  defp process_single_line(state, events, line) do
    case LiveRender.SpecPatch.parse_and_apply(state.spec, line) do
      {:ok, new_spec} ->
        {%{state | spec: new_spec}, events ++ [{:spec, new_spec}]}

      :skip ->
        {state, events}
    end
  end

  # --- One-shot parsing ---

  @spec_fence_regex ~r/```spec\n([\s\S]*?)(?:```|$)/

  defp extract_fence(text) do
    case Regex.run(@spec_fence_regex, text) do
      [_, content] -> {:ok, String.trim(content)}
      nil -> :none
    end
  end

  defp parse_jsonl(content) do
    spec =
      content
      |> String.split("\n")
      |> Enum.reduce(%{"elements" => %{}, "state" => %{}}, fn line, spec ->
        case LiveRender.SpecPatch.parse_and_apply(spec, line) do
          {:ok, new_spec} -> new_spec
          :skip -> spec
        end
      end)

    {:ok, spec}
  end

  defp try_raw_json(text) do
    trimmed = String.trim(text)

    if String.starts_with?(trimmed, "{") do
      case Jason.decode(trimmed) do
        {:ok, %{"root" => _, "elements" => _} = spec} -> {:ok, spec}
        _ -> {:ok, %{}}
      end
    else
      {:ok, %{}}
    end
  end

  # --- Prompt section ---

  defp format_section do
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
    {"op":"add","path":"/elements/card-1","value":{"type":"card","props":{"title":"Stats"},"children":["metric-1","table-1"]}}
    {"op":"add","path":"/elements/metric-1","value":{"type":"metric","props":{"label":"Users","value":"1,234"},"children":[]}}
    {"op":"add","path":"/elements/table-1","value":{"type":"table","props":{"columns":[{"key":"name","label":"Name"}],"data":{"$state":"/items"}},"children":[]}}
    {"op":"add","path":"/state/items","value":[]}
    {"op":"add","path":"/state/items/-","value":{"name":"First"}}
    {"op":"add","path":"/state/items/-","value":{"name":"Second"}}
    ```

    IMPORTANT: Inline scalar values directly in props. Only use {"$state":"/path"} for Table data arrays.
    For arrays, stream one item at a time with the "-" append operator:
    {"op":"add","path":"/state/items","value":[]}
    {"op":"add","path":"/state/items/-","value":{"id":"1","name":"First"}}
    {"op":"add","path":"/state/items/-","value":{"id":"2","name":"Second"}}

    Supported ops: add, replace, remove.
    """
  end
end
