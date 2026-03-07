defmodule Example.Agent do
  @moduledoc """
  AI agent using Jido's ReAct runtime with tool calling.

  Streams ReAct events (`:llm_delta`, `:tool_started`, `:tool_completed`)
  back to the LiveView process as `{:live_render, ...}` messages.
  """

  @default_model "anthropic:claude-haiku-4-5"

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

  @spec_fence_regex ~r/```spec\n([\s\S]*?)(?:```|$)/

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
    model = Keyword.get(opts, :model, @default_model)

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
        text =
          Jido.AI.Reasoning.ReAct.stream(prompt, config)
          |> Enum.reduce("", fn event, text_acc ->
            case event.kind do
              :llm_delta ->
                delta = get_in(event.data, [:delta]) || ""

                if delta != "" do
                  send(pid, {:live_render, :text_chunk, delta})
                end

                text_acc <> delta

              :tool_started ->
                name = event.tool_name || event.data[:tool_name] || "unknown"
                send(pid, {:live_render, :tool_start, name})
                text_acc

              :tool_completed ->
                name = event.tool_name || event.data[:tool_name] || "unknown"
                result = event.data[:result]
                send(pid, {:live_render, :tool_done, name, result})
                text_acc

              :llm_completed ->
                result_text = get_in(event.data, [:result]) || ""

                if result_text != "" and text_acc == "" do
                  send(pid, {:live_render, :text_chunk, result_text})
                  result_text
                else
                  text_acc
                end

              :request_completed ->
                result_text = get_in(event.data, [:result]) || ""

                final_text =
                  if result_text != "" and text_acc == "" do
                    send(pid, {:live_render, :text_chunk, result_text})
                    result_text
                  else
                    text_acc
                  end

                maybe_send_spec(final_text, pid)
                final_text

              :request_failed ->
                error = event.data[:error] || "Unknown error"
                send(pid, {:live_render, :error, error})
                text_acc

              _ ->
                text_acc
            end
          end)

        maybe_send_spec(text, pid)
        send(pid, {:live_render, :done})
      rescue
        e ->
          send(pid, {:live_render, :error, Exception.message(e)})
      end
    end)
  end

  defp maybe_send_spec(text, pid) do
    case Regex.run(@spec_fence_regex, text) do
      [_, json] ->
        case Jason.decode(String.trim(json)) do
          {:ok, %{"root" => _, "elements" => _} = spec} ->
            send(pid, {:live_render, :spec, spec})

          _ ->
            :ok
        end

      nil ->
        trimmed = String.trim(text)

        if String.starts_with?(trimmed, "{") do
          case Jason.decode(trimmed) do
            {:ok, %{"root" => _, "elements" => _} = spec} ->
              send(pid, {:live_render, :spec, spec})

            _ ->
              :ok
          end
        end
    end
  end

  defp build_system_prompt do
    catalog_prompt = Example.Catalog.system_prompt(custom_rules: @custom_rules)

    """
    You are a knowledgeable assistant that helps users explore data and learn about any topic.
    You look up real-time information, build visual dashboards, and create rich educational content.

    WORKFLOW:
    1. Call the appropriate tools to gather relevant data.
    2. Respond with a brief, conversational summary of what you found.
    3. Then output a JSON UI spec wrapped in a ```spec fence to render a rich visual experience.

    RULES:
    - Always call tools FIRST to get real data. Never make up data.
    - Embed fetched data directly in the "state" object so components can reference it with {"$state": "/path"}.
    - Use Card components to group related information.
    - NEVER nest a Card inside another Card. Use Stack, Separator, or Heading inside Cards.
    - Use Grid for multi-column layouts.
    - Use Metric for key numeric values (temperature, stars, price, etc.).
    - Use Table for lists of items (stories, forecasts, languages, etc.).
    - Use Tabs when showing multiple categories of data side by side.
    - Use Badge for status indicators.
    - Use Callout for key facts, tips, warnings, or important takeaways.
    - Use Accordion to organize detailed sections the user can expand.
    - Use Timeline for historical events, processes, or milestones.

    SPEC FORMAT:
    Output a JSON object wrapped in a ```spec fence:

    ```spec
    {
      "root": "root-id",
      "state": { ... },
      "elements": {
        "root-id": { "type": "stack", "props": { "direction": "vertical" }, "children": [...] },
        ...
      }
    }
    ```

    DATA BINDING:
    - Put fetched data in "state", then reference it with {"$state": "/json/pointer"} in any prop.
    - For Table, use {"$state": "/path"} on the data prop.
    - Conditional: {"$cond": {"$state": "/flag"}, "$then": "yes", "$else": "no"}

    #{catalog_prompt}
    """
  end
end
