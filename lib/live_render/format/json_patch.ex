defmodule LiveRender.Format.JSONPatch do
  @moduledoc """
  JSONL RFC 6902 patch format for progressive streaming.

  The LLM outputs one JSON patch operation per line inside a `` ```spec `` fence.
  Each line adds or modifies a part of the spec, so the UI fills in progressively.
  """

  @behaviour LiveRender.Format

  alias LiveRender.Format.Shared

  alias LiveRender.SpecMerge

  @impl true
  def prompt(component_map, actions, opts) do
    format_section()
    |> Shared.json_prompt(component_map, actions, opts)
    |> Shared.with_edit_mode(opts, &edit_section/0)
  end

  @impl true
  def parse(text, opts \\ []) do
    current_spec = Keyword.get(opts, :current_spec)

    case extract_fence(text) do
      {:ok, content} -> parse_jsonl(content, current_spec)
      :none -> try_raw_json(text, current_spec)
    end
  end

  @impl true
  def stream_init(opts \\ []) do
    current_spec = Keyword.get(opts, :current_spec)
    base_spec = current_spec || %{"root" => nil, "elements" => %{}, "state" => %{}}

    %{
      buffer: "",
      in_fence: false,
      spec: base_spec,
      current_spec: current_spec
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

  defp process_single_line(state, events, "") do
    {state, events}
  end

  defp process_single_line(state, events, "//" <> _) do
    {state, events}
  end

  defp process_single_line(state, events, line) do
    case Jason.decode(line) do
      {:ok, %{"__lr_edit" => true} = merge_patch} ->
        new_spec = SpecMerge.merge(state.spec, Map.delete(merge_patch, "__lr_edit"))
        {%{state | spec: new_spec}, events ++ [{:spec, new_spec}]}

      {:ok, %{"op" => _, "path" => _} = patch} ->
        new_spec = LiveRender.SpecPatch.apply(state.spec, patch)
        {%{state | spec: new_spec}, events ++ [{:spec, new_spec}]}

      _ ->
        {state, events}
    end
  end

  # --- One-shot parsing ---

  defp extract_fence(text) do
    Shared.extract_fence(text)
  end

  defp parse_jsonl(content, current_spec) do
    base_spec = current_spec || %{"elements" => %{}, "state" => %{}}

    spec =
      content
      |> String.split("\n")
      |> Enum.reduce(base_spec, &apply_line/2)

    {:ok, spec}
  end

  defp apply_line(line, spec) do
    trimmed = String.trim(line)

    if trimmed == "" or String.starts_with?(trimmed, "//") do
      spec
    else
      case Jason.decode(trimmed) do
        {:ok, %{"__lr_edit" => true} = merge_patch} ->
          SpecMerge.merge(spec, Map.delete(merge_patch, "__lr_edit"))

        {:ok, %{"op" => _, "path" => _} = patch} ->
          LiveRender.SpecPatch.apply(spec, patch)

        _ ->
          spec
      end
    end
  end

  defp try_raw_json(text, _current_spec) do
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

  defp edit_section do
    """
    ## Editing existing specs (merge)

    When editing an existing spec, you can output a single JSON merge line instead of patches.
    Set "__lr_edit" to true and include only the keys that changed.
    Unmentioned keys are preserved. Set a key to null to delete it.

    Example (update title, add element):
    ```spec
    {"__lr_edit":true,"elements":{"heading":{"props":{"title":"New Title"}},"new-chart":{"type":"chart","props":{},"children":[]}}}
    ```

    Example (delete an element):
    ```spec
    {"__lr_edit":true,"elements":{"old-widget":null}}
    ```

    You may also mix merge lines with patch operations in the same fence.
    """
  end
end
