defmodule ExampleWeb.ChatLive do
  use ExampleWeb, :live_view

  @suggestions [
    %{label: "Weather comparison", prompt: "Compare the weather in New York, London, and Tokyo"},
    %{label: "GitHub repo stats", prompt: "Show me stats for the vercel/next.js GitHub repo"},
    %{label: "Crypto dashboard", prompt: "Build a crypto dashboard for Bitcoin and Ethereum"},
    %{label: "Hacker News", prompt: "Show me the top 10 Hacker News stories right now"}
  ]

  @tool_labels %{
    "get_weather" => {"Getting weather data", "Got weather data"},
    "get_github_repo" => {"Fetching GitHub repo", "Fetched GitHub repo"},
    "get_crypto_price" => {"Looking up crypto price", "Looked up crypto price"},
    "get_crypto_price_history" => {"Fetching price history", "Fetched price history"},
    "get_hackernews_top" => {"Loading Hacker News", "Loaded Hacker News"}
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "LiveRender Chat",
       messages: [],
       current_text: "",
       current_spec: %{},
       tool_calls: [],
       streaming?: false,
       form: to_form(%{"prompt" => ""})
     )}
  end

  @impl true
  def handle_event("submit", %{"prompt" => prompt}, socket) when prompt != "" do
    user_msg = %{
      id: System.unique_integer([:positive]),
      role: :user,
      content: prompt
    }

    context = build_context(socket.assigns.messages)
    Example.Agent.chat(prompt, self(), context: context)

    {:noreply,
     assign(socket,
       messages: socket.assigns.messages ++ [user_msg],
       current_text: "",
       current_spec: %{},
       tool_calls: [],
       streaming?: true,
       form: to_form(%{"prompt" => ""})
     )}
  end

  def handle_event("submit", _params, socket), do: {:noreply, socket}

  def handle_event("suggest", %{"prompt" => prompt}, socket) do
    handle_event("submit", %{"prompt" => prompt}, socket)
  end

  def handle_event("clear", _, socket) do
    {:noreply,
     assign(socket,
       messages: [],
       current_text: "",
       current_spec: %{},
       tool_calls: [],
       streaming?: false,
       form: to_form(%{"prompt" => ""})
     )}
  end

  @impl true
  def handle_info({:live_render, :text_chunk, token}, socket) do
    {:noreply, assign(socket, :current_text, socket.assigns.current_text <> token)}
  end

  def handle_info({:live_render, :tool_start, name}, socket) do
    call = %{name: name, status: :running}
    {:noreply, assign(socket, :tool_calls, socket.assigns.tool_calls ++ [call])}
  end

  def handle_info({:live_render, :tool_done, name, _result}, socket) do
    tool_calls =
      Enum.map(socket.assigns.tool_calls, fn
        %{name: ^name, status: :running} = c -> %{c | status: :done}
        c -> c
      end)

    {:noreply, assign(socket, :tool_calls, tool_calls)}
  end

  def handle_info({:live_render, :spec, spec}, socket) do
    {:noreply, assign(socket, :current_spec, spec)}
  end

  def handle_info({:live_render, :done}, socket) do
    text = strip_spec_fence(socket.assigns.current_text)

    assistant_msg = %{
      id: System.unique_integer([:positive]),
      role: :assistant,
      content: text,
      spec: socket.assigns.current_spec,
      tool_calls: socket.assigns.tool_calls
    }

    {:noreply,
     assign(socket,
       messages: socket.assigns.messages ++ [assistant_msg],
       current_text: "",
       current_spec: %{},
       tool_calls: [],
       streaming?: false
     )}
  end

  def handle_info({:live_render, :error, reason}, socket) do
    {:noreply,
     socket
     |> assign(:streaming?, false)
     |> put_flash(:error, "Error: #{inspect(reason)}")}
  end

  defp build_context(messages) do
    Enum.flat_map(messages, fn
      %{role: :user, content: content} -> [ReqLLM.Context.user(content)]
      %{role: :assistant, content: content} -> [ReqLLM.Context.assistant(content)]
      _ -> []
    end)
  end

  defp strip_spec_fence(text) do
    text
    |> String.replace(~r/```spec\n[\s\S]*?(?:```|$)/, "")
    |> String.trim()
  end

  defp tool_label(name, :running), do: elem(Map.get(@tool_labels, name, {name, name}), 0)
  defp tool_label(name, _), do: elem(Map.get(@tool_labels, name, {name, name}), 1)

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :suggestions, @suggestions)

    ~H"""
    <div class="flex flex-col h-dvh max-w-4xl mx-auto">
      <header class="shrink-0 flex items-center justify-between px-6 py-3 border-b border-gray-200 dark:border-gray-800">
        <h1 class="text-lg font-semibold">LiveRender Chat</h1>
        <button
          :if={@messages != []}
          phx-click="clear"
          class="text-sm text-gray-500 hover:text-gray-900 dark:hover:text-gray-100"
        >
          Start Over
        </button>
      </header>

      <div id="messages" class="flex-1 overflow-y-auto px-6 py-6 space-y-6" phx-hook="ScrollBottom">
        <%!-- Empty state --%>
        <div :if={@messages == [] and not @streaming?} class="flex flex-col items-center justify-center h-full">
          <div class="max-w-2xl w-full space-y-8 text-center">
            <div>
              <h2 class="text-2xl font-semibold tracking-tight">What would you like to explore?</h2>
              <p class="mt-2 text-gray-500">
                Ask about weather, GitHub repos, crypto prices, or Hacker News —
                the agent will fetch real data and build a dashboard.
              </p>
            </div>
            <div class="flex flex-wrap gap-2 justify-center">
              <button
                :for={s <- @suggestions}
                phx-click="suggest"
                phx-value-prompt={s.prompt}
                class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full border text-sm text-gray-600 dark:text-gray-400 hover:bg-gray-50 dark:hover:bg-gray-800 transition"
              >
                ✦ {s.label}
              </button>
            </div>
          </div>
        </div>

        <%!-- Message history --%>
        <div :for={msg <- @messages} class={["rounded-xl px-5 py-4", msg_bg(msg.role)]}>
          <div class="flex items-center gap-2 mb-2">
            <div class={["size-5 rounded-full flex items-center justify-center text-[10px] font-bold", avatar_class(msg.role)]}>
              {if msg.role == :user, do: "Y", else: "A"}
            </div>
            <span class="text-xs font-medium text-gray-500">
              {if msg.role == :user, do: "You", else: "Assistant"}
            </span>
          </div>

          <%!-- Tool calls --%>
          <div :if={Map.get(msg, :tool_calls, []) != []} class="pl-7 mb-2 flex flex-col gap-1">
            <div :for={tc <- msg.tool_calls} class="text-sm text-gray-500">
              ✓ {tool_label(tc.name, tc.status)}
            </div>
          </div>

          <%!-- Text content --%>
          <div :if={msg.content != ""} class="psd-prose pl-7">
            <PhoenixStreamdown.markdown content={msg.content} id={"msg-#{msg.id}"} />
          </div>

          <%!-- Rendered spec --%>
          <div :if={Map.get(msg, :spec, %{}) != %{}} class="mt-4">
            <LiveRender.render spec={msg.spec} catalog={Example.Catalog} id={"spec-#{msg.id}"} />
          </div>
        </div>

        <%!-- Currently streaming assistant --%>
        <div :if={@streaming?} class="rounded-xl px-5 py-4 bg-gray-50 dark:bg-gray-900/50">
          <div class="flex items-center gap-2 mb-2">
            <div class="size-5 rounded-full bg-green-100 dark:bg-green-900/30 text-green-600 flex items-center justify-center text-[10px] font-bold">
              A
            </div>
            <span class="text-xs font-medium text-gray-500">Assistant</span>
            <span :if={@current_text == "" and @tool_calls == []} class="flex gap-0.5 ml-1">
              <span class="size-1 rounded-full bg-gray-400 animate-bounce [animation-delay:0ms]" />
              <span class="size-1 rounded-full bg-gray-400 animate-bounce [animation-delay:150ms]" />
              <span class="size-1 rounded-full bg-gray-400 animate-bounce [animation-delay:300ms]" />
            </span>
          </div>

          <%!-- Active tool calls --%>
          <div :if={@tool_calls != []} class="pl-7 mb-2 flex flex-col gap-1">
            <div :for={tc <- @tool_calls} class="text-sm text-gray-500 flex items-center gap-1.5">
              <span :if={tc.status == :running} class="inline-block size-3 border-2 border-gray-400 border-t-transparent rounded-full animate-spin" />
              <span :if={tc.status != :running}>✓</span>
              {tool_label(tc.name, tc.status)}
            </div>
          </div>

          <%!-- Streaming text --%>
          <div :if={@current_text != ""} class="psd-prose pl-7">
            <PhoenixStreamdown.markdown content={strip_spec_fence(@current_text)} streaming id="streaming" />
          </div>

          <%!-- Streaming spec --%>
          <div :if={@current_spec != %{}} class="mt-4">
            <LiveRender.render spec={@current_spec} catalog={Example.Catalog} streaming id="streaming-spec" />
          </div>
        </div>
      </div>

      <%!-- Input --%>
      <div class="shrink-0 px-6 py-4 border-t border-gray-200 dark:border-gray-800">
        <.form for={@form} phx-submit="submit" class="flex gap-3 items-center">
          <input
            type="text"
            name="prompt"
            value={@form[:prompt].value}
            placeholder={if @messages == [], do: "e.g., Compare weather in NYC, London, and Tokyo...", else: "Ask a follow-up..."}
            class="flex-1 rounded-xl border border-gray-300 dark:border-gray-700 bg-white dark:bg-gray-900 px-4 py-3 text-sm focus:outline-none focus:ring-1 focus:ring-blue-500"
            autocomplete="off"
            autofocus
            disabled={@streaming?}
          />
          <button
            type="submit"
            disabled={@streaming?}
            class="h-10 w-10 rounded-lg bg-blue-600 text-white flex items-center justify-center hover:bg-blue-700 disabled:opacity-50 transition"
          >
            <span :if={@streaming?} class="inline-block size-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
            <svg :if={not @streaming?} xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-5">
              <path d="M3.105 2.288a.75.75 0 0 0-.826.95l1.414 4.926A1.5 1.5 0 0 0 5.135 9.25h6.115a.75.75 0 0 1 0 1.5H5.135a1.5 1.5 0 0 0-1.442 1.086l-1.414 4.926a.75.75 0 0 0 .826.95 28.897 28.897 0 0 0 15.293-7.154.75.75 0 0 0 0-1.115A28.897 28.897 0 0 0 3.105 2.288Z" />
            </svg>
          </button>
        </.form>
      </div>
    </div>
    """
  end

  defp msg_bg(:user), do: "bg-blue-50/50 dark:bg-blue-950/20"
  defp msg_bg(_), do: "bg-gray-50 dark:bg-gray-900/50"

  defp avatar_class(:user), do: "bg-blue-100 dark:bg-blue-900/30 text-blue-600"
  defp avatar_class(_), do: "bg-green-100 dark:bg-green-900/30 text-green-600"
end
