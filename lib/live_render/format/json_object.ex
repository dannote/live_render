defmodule LiveRender.Format.JSONObject do
  @moduledoc """
  Single JSON object format.

  The LLM outputs a complete JSON object with `root`, `elements`, and optional `state`
  inside a `` ```spec `` fence.
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
      {:ok, json} -> parse_json(json, current_spec)
      :none -> try_raw_json(text, current_spec)
    end
  end

  @impl true
  def stream_init(opts \\ []) do
    %{buffer: "", in_fence: false, current_spec: Keyword.get(opts, :current_spec)}
  end

  @impl true
  def stream_push(state, chunk) do
    Shared.stream_push(state, chunk, &process_fence_buffer/2)
  end

  @impl true
  def stream_flush(state) do
    if state.in_fence and state.buffer != "" do
      events = parse_with_repair(state.buffer, state.current_spec)
      {%{state | buffer: "", in_fence: false}, events}
    else
      {state, []}
    end
  end

  defp process_fence_buffer(state, buf) do
    case String.split(buf, "```", parts: 2) do
      [content, _rest] ->
        events = parse_with_repair(content, state.current_spec)
        {%{state | buffer: content, in_fence: false}, events}

      [_] ->
        events = parse_with_repair(buf, state.current_spec)
        {%{state | buffer: buf}, events}
    end
  end

  defp parse_with_repair(content, current_spec) do
    trimmed = String.trim(content)

    if trimmed == "" do
      []
    else
      repaired = LiveRender.JSONRepair.repair(trimmed)

      case Jason.decode(repaired) do
        {:ok, %{"root" => _, "elements" => _} = spec} ->
          [{:spec, spec}]

        {:ok, parsed} when is_map(parsed) and not is_nil(current_spec) ->
          [{:spec, SpecMerge.merge(current_spec, parsed)}]

        _ ->
          []
      end
    end
  end

  @spec_fence_regex ~r/```spec\n([\s\S]*?)(?:```|$)/

  defp extract_fence(text) do
    case Regex.run(@spec_fence_regex, text) do
      [_, content] -> {:ok, String.trim(content)}
      nil -> :none
    end
  end

  defp parse_json(json, current_spec) do
    case Jason.decode(json) do
      {:ok, %{"root" => _, "elements" => _} = spec} ->
        {:ok, spec}

      {:ok, parsed} when is_map(parsed) and not is_nil(current_spec) ->
        {:ok, SpecMerge.merge(current_spec, parsed)}

      {:ok, _} ->
        {:ok, %{}}

      {:error, _} ->
        {:ok, %{}}
    end
  end

  defp try_raw_json(text, current_spec) do
    trimmed = String.trim(text)

    if String.starts_with?(trimmed, "{") do
      parse_json(trimmed, current_spec)
    else
      {:ok, %{}}
    end
  end

  defp format_section do
    """
    ## Spec format

    Output a JSON object with:
    - "root": string ID of the root element
    - "state": object with initial state values (optional)
    - "elements": object mapping element IDs to element definitions

    Each element: {"type": "component_name", "props": {...}, "children": ["child-id", ...]}
    """
  end

  defp edit_section do
    """
    ## Editing existing specs (merge)

    When editing an existing spec, output ONLY the changed parts in a ```spec fence.
    Uses deep merge: only keys you include are updated. Unmentioned elements and props are preserved.
    Set a key to null to delete it.

    Example edit (update title, add element):
    ```spec
    {"elements":{"heading":{"props":{"title":"New Title"}},"new-chart":{"type":"chart","props":{},"children":[]}}}
    ```

    Example deletion:
    ```spec
    {"elements":{"old-widget":null}}
    ```
    """
  end
end
