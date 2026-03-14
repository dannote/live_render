if Code.ensure_loaded?(YamlElixir) do
  defmodule LiveRender.Format.YAML do
    @moduledoc """
    YAML wire format for progressive streaming.

    The LLM outputs a YAML document inside a `` ```spec `` fence. The streaming
    parser incrementally re-parses on each newline and emits `{:spec, spec}`
    events whenever the parsed result changes, so the UI fills in progressively.

    YAML is more token-efficient than JSON for LLM generation — no quotes on keys,
    no commas, no braces — while producing the same spec structure.

    When a `:current_spec` is provided via opts, the format supports merge edits:
    the LLM outputs only the changed keys and they are deep-merged into the
    existing spec using RFC 7396 semantics.

    Note: a YAML document containing both `root` and `elements` top-level keys
    is treated as a full spec replacement, not a merge edit. Edits that need to
    change `root` while also updating elements should include all keys.
    """

    @behaviour LiveRender.Format

    alias LiveRender.Format.Shared
    alias LiveRender.SpecMerge

    @impl true
    def prompt(component_map, actions, opts) do
      Shared.yaml_prompt(format_section(), edit_section(), component_map, actions, opts)
    end

    @impl true
    def parse(text, opts \\ []) do
      current_spec = Keyword.get(opts, :current_spec)

      case extract_fence(text) do
        {:ok, content} -> parse_yaml(content, current_spec)
        :none -> try_raw_yaml(text, current_spec)
      end
    end

    @impl true
    def stream_init(opts \\ []) do
      current_spec = Keyword.get(opts, :current_spec, %{})

      %{
        buffer: "",
        in_fence: false,
        merge_base: current_spec,
        spec: current_spec
      }
    end

    @impl true
    def stream_push(state, chunk) do
      Shared.stream_push(state, chunk, &process_fence_buffer/2)
    end

    @impl true
    def stream_flush(state) do
      if state.in_fence and state.buffer != "" do
        {state, events} = try_parse(state, state.buffer)
        {%{state | buffer: "", in_fence: false}, events}
      else
        {state, []}
      end
    end

    # --- Fence processing ---

    defp process_fence_buffer(state, buf) do
      case String.split(buf, "```", parts: 2) do
        [content, _rest] ->
          {state, events} = try_parse(state, content)
          {%{state | buffer: content, in_fence: false}, events}

        [_] ->
          if String.contains?(buf, "\n") do
            {state, events} = try_parse(state, buf)
            {%{state | buffer: buf}, events}
          else
            {%{state | buffer: buf}, []}
          end
      end
    end

    defp try_parse(state, content) do
      case parse_trimmed(String.trim(content)) do
        nil ->
          {state, []}

        parsed ->
          spec = maybe_merge(state.merge_base, parsed)

          if spec != state.spec do
            {%{state | spec: spec}, [{:spec, spec}]}
          else
            {state, []}
          end
      end
    end

    defp parse_trimmed(""), do: nil

    defp parse_trimmed(yaml) do
      case YamlElixir.read_from_string(yaml) do
        {:ok, parsed} when is_map(parsed) -> parsed
        _ -> nil
      end
    end

    defp maybe_merge(merge_base, parsed) when map_size(merge_base) == 0, do: parsed

    defp maybe_merge(merge_base, parsed) do
      if Map.has_key?(parsed, "root") and Map.has_key?(parsed, "elements") do
        parsed
      else
        SpecMerge.merge(merge_base, parsed)
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

    defp parse_yaml(content, current_spec) do
      case YamlElixir.read_from_string(content) do
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

    defp try_raw_yaml(text, current_spec) do
      trimmed = String.trim(text)

      if trimmed != "" and not String.starts_with?(trimmed, "{") do
        parse_yaml(trimmed, current_spec)
      else
        {:ok, %{}}
      end
    end

    # --- Prompt sections ---

    defp format_section do
      """
      ## Spec format (YAML)

      Output a YAML document inside a ```spec fence.
      The document has three top-level keys: root, elements, and state (optional).

      Each element: {type: component_name, props: {...}, children: [child-id, ...]}

      Stream progressively — output elements one at a time so the UI fills in as you write.

      Example:
      ```spec
      root: main
      elements:
        main:
          type: stack
          props: {}
          children:
            - heading
            - card-1
        heading:
          type: heading
          props:
            text: Dashboard
          children: []
        card-1:
          type: card
          props:
            title: Stats
          children:
            - metric-1
        metric-1:
          type: metric
          props:
            label: Users
            value: "1,234"
          children: []
      state: {}
      ```

      IMPORTANT: String values that look like numbers must be quoted (e.g. "1,234").
      Use snake_case for component type names.
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
      elements:
        heading:
          props:
            text: Updated Title
        new-chart:
          type: chart
          props: {}
          children: []
      ```

      Example deletion:
      ```spec
      elements:
        old-widget: null
      ```
      """
    end
  end
end
