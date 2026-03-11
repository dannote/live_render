defmodule LiveRender.Format.JSONObject do
  @moduledoc """
  Single JSON object format.

  The LLM outputs a complete JSON object with `root`, `elements`, and optional `state`
  inside a `` ```spec `` fence.
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
      {:ok, json} -> parse_json(json)
      :none -> try_raw_json(text)
    end
  end

  @impl true
  def stream_init(_opts \\ []) do
    %{buffer: "", in_fence: false}
  end

  @impl true
  def stream_push(state, chunk) do
    Shared.stream_push(state, chunk, &process_fence_buffer/2)
  end

  @impl true
  def stream_flush(state) do
    if state.in_fence and state.buffer != "" do
      events = parse_with_repair(state.buffer)
      {%{state | buffer: "", in_fence: false}, events}
    else
      {state, []}
    end
  end

  defp process_fence_buffer(state, buf) do
    case String.split(buf, "```", parts: 2) do
      [content, _rest] ->
        events = parse_with_repair(content)
        {%{state | buffer: content, in_fence: false}, events}

      [_] ->
        events = parse_with_repair(buf)
        {%{state | buffer: buf}, events}
    end
  end

  defp parse_with_repair(content) do
    trimmed = String.trim(content)

    if trimmed == "" do
      []
    else
      repaired = LiveRender.JSONRepair.repair(trimmed)

      case Jason.decode(repaired) do
        {:ok, %{"root" => _, "elements" => _} = spec} -> [{:spec, spec}]
        _ -> []
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

  defp parse_json(json) do
    case Jason.decode(json) do
      {:ok, %{"root" => _, "elements" => _} = spec} -> {:ok, spec}
      {:ok, _} -> {:ok, %{}}
      {:error, _} -> {:ok, %{}}
    end
  end

  defp try_raw_json(text) do
    trimmed = String.trim(text)

    if String.starts_with?(trimmed, "{") do
      parse_json(trimmed)
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
end
