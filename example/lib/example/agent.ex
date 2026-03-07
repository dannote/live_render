defmodule Example.Agent do
  @moduledoc """
  AI agent with tool calling that generates LiveRender specs.

  Streams text tokens back to the caller process and, once complete,
  extracts any `spec` fence into a parsed spec map.
  """

  @default_model "anthropic:claude-haiku-4-5"
  @max_tool_rounds 5

  @spec_fence_regex ~r/```spec\n([\s\S]*?)(?:```|$)/

  @custom_rules [
    "NEVER use viewport height classes (min-h-screen, h-screen) — the UI renders inside a fixed-size container.",
    "Prefer Grid with columns='2' or columns='3' for side-by-side layouts.",
    "Use Metric components for key numbers instead of plain Text.",
    "Keep the UI clean and information-dense — no excessive padding or empty space.",
    "For educational prompts ('teach me about', 'explain', 'what is'), use a mix of Callout, Accordion, Timeline to make the content visually rich."
  ]

  defp tools do
    [
      Example.Tools.Weather.tool(),
      Example.Tools.Crypto.price_tool(),
      Example.Tools.Crypto.history_tool(),
      Example.Tools.GitHub.repo_tool(),
      Example.Tools.HackerNews.tool()
    ]
  end

  @doc """
  Starts a conversation with the agent.

  Sends these messages to `pid`:
  - `{:live_render, :tool_start, name}` — a tool call is starting
  - `{:live_render, :tool_done, name, result}` — a tool call finished
  - `{:live_render, :text_chunk, token}` — streaming text token
  - `{:live_render, :spec, spec}` — parsed UI spec
  - `{:live_render, :done}` — generation complete
  - `{:live_render, :error, reason}` — something went wrong
  """
  def chat(prompt, pid, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)
    context = Keyword.get(opts, :context, [])

    Task.start(fn ->
      system = build_system_prompt()

      messages =
        ReqLLM.Context.new(
          [ReqLLM.Context.system(system)] ++
            context ++
            [ReqLLM.Context.user(prompt)]
        )

      case run_with_tools(model, messages, tools(), pid, 0) do
        {:ok, _text} -> send(pid, {:live_render, :done})
        {:error, reason} -> send(pid, {:live_render, :error, reason})
      end
    end)
  end

  defp run_with_tools(model, messages, tools, pid, round) when round < @max_tool_rounds do
    case ReqLLM.stream_text(model, messages.messages, tools: tools) do
      {:ok, response} ->
        {text, tool_calls} = consume_stream(response, pid)

        if tool_calls == [] do
          maybe_send_spec(text, pid)
          {:ok, text}
        else
          assistant_msg = ReqLLM.Context.assistant(text, tool_calls: tool_calls)
          messages = ReqLLM.Context.append(messages, assistant_msg)

          messages = execute_tools(tool_calls, tools, messages, pid)

          run_with_tools(model, messages, tools, pid, round + 1)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_with_tools(model, messages, _tools, pid, _round) do
    case ReqLLM.stream_text(model, messages.messages) do
      {:ok, response} ->
        {text, _} = consume_stream(response, pid)
        maybe_send_spec(text, pid)
        {:ok, text}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp consume_stream(response, pid) do
    chunks =
      response.stream
      |> Enum.map(fn chunk ->
        if chunk.text && chunk.text != "" do
          send(pid, {:live_render, :text_chunk, chunk.text})
        end

        chunk
      end)

    text = chunks |> Enum.map_join("", & &1.text)
    tool_calls = extract_tool_calls(chunks)

    {text, tool_calls}
  end

  defp extract_tool_calls(chunks) do
    base_calls =
      chunks
      |> Enum.filter(&(&1.type == :tool_call))
      |> Enum.map(fn chunk ->
        %{
          id: Map.get(chunk.metadata, :id) || "call_#{:erlang.unique_integer([:positive])}",
          name: chunk.name,
          arguments: chunk.arguments || %{},
          index: Map.get(chunk.metadata, :index, 0)
        }
      end)

    arg_fragments =
      chunks
      |> Enum.filter(fn
        %{type: :meta, metadata: %{tool_call_args: _}} -> true
        _ -> false
      end)
      |> Enum.group_by(& &1.metadata.tool_call_args.index)
      |> Map.new(fn {index, frags} ->
        json = frags |> Enum.map_join("", & &1.metadata.tool_call_args.fragment)
        {index, json}
      end)

    base_calls
    |> Enum.map(fn call ->
      call =
        case Map.get(arg_fragments, call.index) do
          nil ->
            call

          json ->
            case Jason.decode(json) do
              {:ok, args} -> %{call | arguments: args}
              _ -> call
            end
        end

      Map.delete(call, :index)
    end)
  end

  defp execute_tools(tool_calls, tools, messages, pid) do
    Enum.reduce(tool_calls, messages, fn call, ctx ->
      send(pid, {:live_render, :tool_start, call.name})

      tool = Enum.find(tools, &(&1.name == call.name))

      {result_text, _} =
        if tool do
          case ReqLLM.Tool.execute(tool, call.arguments) do
            {:ok, result} ->
              send(pid, {:live_render, :tool_done, call.name, result})
              {Jason.encode!(result), result}

            {:error, error} ->
              msg = inspect(error)
              send(pid, {:live_render, :tool_done, call.name, %{error: msg}})
              {Jason.encode!(%{error: msg}), nil}
          end
        else
          send(pid, {:live_render, :tool_done, call.name, %{error: "unknown tool"}})
          {Jason.encode!(%{error: "Tool #{call.name} not found"}), nil}
        end

      tool_result = ReqLLM.Context.tool_result_message(call.name, call.id, result_text)
      ReqLLM.Context.append(ctx, tool_result)
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
