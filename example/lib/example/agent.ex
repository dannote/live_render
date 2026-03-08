defmodule Example.Agent do
  @moduledoc """
  AI agent using Jido's ReAct runtime with tool calling.

  Streams ReAct events (`:llm_delta`, `:tool_started`, `:tool_completed`)
  back to the LiveView process as `{:live_render, ...}` messages.
  """

  @default_model "anthropic:claude-haiku-4-5"

  defp default_model do
    Application.get_env(:example, :model, @default_model)
  end

  @tools [
    Example.Tools.Weather,
    Example.Tools.CryptoPrice,
    Example.Tools.CryptoPriceHistory,
    Example.Tools.GitHubRepo,
    Example.Tools.HackerNews
  ]

  @custom_rules [
    "NEVER use viewport height classes (min-h-screen, h-screen) — the UI renders inside a fixed-size container.",
    "Prefer Grid with columns='2' or columns='3' for side-by-side layouts.",
    "Use Metric components for key numbers instead of plain Text.",
    "Keep the UI clean and information-dense — no excessive padding or empty space.",
    "For educational prompts ('teach me about', 'explain', 'what is'), use a mix of Callout, Accordion, Timeline to make the content visually rich."
  ]



  @doc """
  Starts a streamed conversation with the ReAct agent.

  Sends messages to `pid`:
  - `{:live_render, :tool_start, name}` — tool execution started
  - `{:live_render, :tool_done, name, result}` — tool execution finished
  - `{:live_render, :text_chunk, text}` — streaming text delta
  - `{:live_render, :spec, spec}` — parsed UI spec
  - `{:live_render, :done}` — generation complete
  - `{:live_render, :error, reason}` — failure
  """
  def chat(prompt, pid, opts \\ []) do
    model = Keyword.get(opts, :model, default_model())

    Task.start(fn ->
      config = %{
        model: model,
        system_prompt: build_system_prompt(),
        tools: @tools,
        max_iterations: 5,
        streaming: true,
        temperature: 0.7,
        max_tokens: 4096
      }

      try do
        initial_acc = %{
          line_buf: "",
          last_tool_iter: nil,
          in_fence: false,
          spec: %{"root" => nil, "elements" => %{}, "state" => %{}}
        }

        Jido.AI.Reasoning.ReAct.stream(prompt, config)
        |> Enum.reduce(initial_acc, fn event, acc ->
          case event.kind do
            :llm_delta ->
              delta = get_in(event.data, [:delta]) || ""
              if delta == "", do: acc, else: process_delta(delta, acc, pid)

            :tool_started ->
              name = event.tool_name || event.data[:tool_name] || "unknown"
              send(pid, {:live_render, :tool_start, name})
              %{acc | last_tool_iter: event.iteration, line_buf: "", in_fence: false}

            :tool_completed ->
              name = event.tool_name || event.data[:tool_name] || "unknown"
              send(pid, {:live_render, :tool_done, name, event.data[:result]})
              %{acc | last_tool_iter: event.iteration}

            :request_failed ->
              send(pid, {:live_render, :error, event.data[:error] || "Unknown error"})
              acc

            _ ->
              acc
          end
        end)

        send(pid, {:live_render, :done})
      rescue
        e ->
          send(pid, {:live_render, :error, Exception.message(e)})
      end
    end)
  end

  defp process_delta(delta, acc, pid) do
    buf = acc.line_buf <> delta

    {lines, remainder} = split_lines(buf)

    acc = Enum.reduce(lines, %{acc | line_buf: ""}, fn line, acc ->
      process_line(line, acc, pid)
    end)

    %{acc | line_buf: remainder}
  end

  defp split_lines(buf) do
    parts = String.split(buf, "\n", parts: :infinity)
    {remainder, complete} = List.pop_at(parts, -1)
    {complete, remainder}
  end

  defp process_line(line, acc, pid) do
    trimmed = String.trim(line)

    cond do
      not acc.in_fence and String.starts_with?(trimmed, "```spec") ->
        %{acc | in_fence: true}

      acc.in_fence and trimmed == "```" ->
        %{acc | in_fence: false}

      acc.in_fence ->
        case LiveRender.SpecPatch.parse_and_apply(acc.spec, trimmed) do
          {:ok, new_spec} ->
            send(pid, {:live_render, :spec, new_spec})
            %{acc | spec: new_spec}

          :skip ->
            acc
        end

      true ->
        send(pid, {:live_render, :text_chunk, line <> "\n"})
        acc
    end
  end

  defp build_system_prompt do
    catalog_prompt = Example.Catalog.system_prompt(mode: :patch, custom_rules: @custom_rules)

    """
    You are a knowledgeable assistant that helps users explore data and learn about any topic.
    You look up real-time information, build visual dashboards, and create rich educational content.

    WORKFLOW:
    1. Call the appropriate tools to gather relevant data.
    2. Respond with a brief, conversational summary of what you found (1-3 sentences).
    3. Then output the JSONL UI spec wrapped in a ```spec fence to render a rich visual experience.

    RULES:
    - Always call tools FIRST to get real data. Never make up data.
    - INLINE data values directly in component props. Do NOT use {"$state": "/path"} for scalar values.
      CORRECT: {"type":"metric","props":{"label":"Temperature","value":"48°F"},"children":[]}
      WRONG:   {"type":"metric","props":{"label":"Temperature","value":{"$state":"/temp"}},"children":[]}
    - The ONLY use for $state is Table data arrays that stream row-by-row:
      {"type":"table","props":{"data":{"$state":"/forecast"},...},"children":[]}
      Then: {"op":"add","path":"/state/forecast","value":[]}
      Then: {"op":"add","path":"/state/forecast/-","value":{"day":"Mon",...}}
    - Use Card components to group related information.
    - NEVER nest a Card inside another Card. Use Stack, Separator, or Heading inside Cards.
    - Use Grid for multi-column layouts.
    - Use Metric for key numeric values (temperature, stars, price, etc.).
    - Use Table for lists of items (stories, forecasts, languages, etc.).
    - Use Badge for status indicators.
    - Use Callout for key facts, tips, warnings, or important takeaways.
    - Use Accordion to organize detailed sections the user can expand.
    - Use Timeline for historical events, processes, or milestones.
    - If the user's message does not require a UI, respond with text only — no spec fence.

    #{catalog_prompt}
    """
  end
end
