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

  @formats [
    {"jsonl", LiveRender.Format.JSONPatch, "JSONL patches"},
    {"json", LiveRender.Format.JSONObject, "JSON object"},
    {"yaml", LiveRender.Format.YAML, "YAML"},
    {"olang", LiveRender.Format.OpenUILang, "OpenUI Lang"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "LiveRender Chat",
       messages: [],
       current_text: "",
       after_text: "",
       current_spec: %{}, spec_version: 0,
       tool_calls: [],
       streaming?: false,
       form: to_form(%{"prompt" => ""}),
       format: "jsonl",
       formats: @formats
     )}
  end

  @impl true
  def handle_event("set_format", %{"format" => format_key}, socket) do
    {:noreply, assign(socket, :format, format_key)}
  end

  @impl true
  def handle_event("submit", %{"prompt" => prompt}, socket) when prompt != "" do
    user_msg = %{
      id: System.unique_integer([:positive]),
      role: :user,
      content: prompt
    }

    format_mod = format_module(socket.assigns.format)
    context = build_context(socket.assigns.messages)
    Example.Agent.chat(prompt, self(), context: context, format: format_mod)

    {:noreply,
     assign(socket,
       messages: socket.assigns.messages ++ [user_msg],
       current_text: "",
       after_text: "",
       current_spec: %{}, spec_version: 0,
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
       after_text: "",
       current_spec: %{}, spec_version: 0,
       tool_calls: [],
       streaming?: false,
       form: to_form(%{"prompt" => ""})
     )}
  end

  @impl true
  def handle_info({:live_render, :text_chunk, token}, socket) do
    if socket.assigns.current_spec != %{} do
      {:noreply, assign(socket, :after_text, socket.assigns.after_text <> token)}
    else
      {:noreply, assign(socket, :current_text, socket.assigns.current_text <> token)}
    end
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
    ver = Map.get(socket.assigns, :spec_version, 0) + 1
    {:noreply, assign(socket, current_spec: spec, spec_version: ver)}
  end

  def handle_info({:live_render, :done}, socket) do
    before_text = strip_spec_fence(socket.assigns.current_text)
    after_text = strip_spec_fence(socket.assigns.after_text)

    assistant_msg = %{
      id: System.unique_integer([:positive]),
      role: :assistant,
      content: before_text,
      after_content: after_text,
      spec: socket.assigns.current_spec,
      tool_calls: socket.assigns.tool_calls
    }

    {:noreply,
     assign(socket,
       messages: socket.assigns.messages ++ [assistant_msg],
       current_text: "",
       after_text: "",
       current_spec: %{}, spec_version: 0,
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
    |> String.replace(~r/```(?:spec|yaml)\n[\s\S]*?(?:```|$)/, "")
    |> String.trim()
  end

  defp tool_label(name, :running), do: elem(Map.get(@tool_labels, name, {name, name}), 0)
  defp tool_label(name, _), do: elem(Map.get(@tool_labels, name, {name, name}), 1)

  defp format_module(key) do
    Enum.find_value(@formats, LiveRender.Format.JSONPatch, fn {k, mod, _} ->
      if k == key, do: mod
    end)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :suggestions, @suggestions)

    ~H"""
    <div class="h-dvh flex flex-col overflow-hidden">
      <%!-- Header --%>
      <header class="border-b border-border px-6 py-3 flex items-center justify-between shrink-0">
        <h1 class="text-lg font-semibold">LiveRender Chat</h1>
        <div class="flex items-center gap-3">
          <div class="flex items-center rounded-md border border-border text-[11px] font-mono overflow-hidden">
            <button
              :for={{key, _mod, _label} <- @formats}
              phx-click="set_format"
              phx-value-format={key}
              disabled={@streaming?}
              class={[
                "px-2 py-1 transition-colors disabled:cursor-not-allowed",
                if(@format == key,
                  do: "bg-muted text-foreground",
                  else: "text-muted-foreground hover:text-foreground"
                )
              ]}
            >
              {key}
            </button>
          </div>
          <button
            :if={@messages != []}
            phx-click="clear"
            class="px-3 py-1.5 rounded-md text-sm text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
          >
            Start Over
          </button>
          <button
            phx-click={Phoenix.LiveView.JS.dispatch("phx:toggle-theme")}
            class="h-8 w-8 rounded-md flex items-center justify-center text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
            aria-label="Toggle theme"
          >
            <.icon name="hero-moon" class="size-4 dark:hidden" />
            <.icon name="hero-sun" class="size-4 hidden dark:block" />
          </button>
        </div>
      </header>

      <%!-- Messages area --%>
      <main id="messages" class="flex-1 overflow-auto" phx-hook="ScrollBottom">
        <%!-- Empty state --%>
        <div :if={@messages == [] and not @streaming?} class="h-full flex flex-col items-center justify-center px-6 py-12">
          <div class="max-w-2xl w-full space-y-8">
            <div class="text-center space-y-2">
              <h2 class="text-2xl font-semibold tracking-tight">What would you like to explore?</h2>
              <p class="text-muted-foreground">
                Ask about weather, GitHub repos, crypto prices, or Hacker News —
                the agent will fetch real data and build a dashboard.
              </p>
            </div>
            <div class="flex flex-wrap gap-2 justify-center">
              <button
                :for={s <- @suggestions}
                phx-click="suggest"
                phx-value-prompt={s.prompt}
                class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full border border-border text-sm text-muted-foreground hover:text-foreground hover:bg-accent transition-colors"
              >
                ✦ {s.label}
              </button>
            </div>
          </div>
        </div>

        <%!-- Message thread --%>
        <div :if={@messages != [] or @streaming?} class="max-w-4xl mx-auto px-10 py-6 space-y-6">
          <div :for={msg <- @messages}>
            <%!-- User message: right-aligned bubble --%>
            <div :if={msg.role == :user} class="flex justify-end">
              <div class="inline-block max-w-[85%] rounded-2xl rounded-tr-md px-4 py-2.5 text-sm leading-relaxed whitespace-pre-wrap bg-primary text-primary-foreground">{msg.content}</div>
            </div>

            <%!-- Assistant message: full-width, no bubble --%>
            <div :if={msg.role == :assistant} class="w-full flex flex-col gap-3">
              <%!-- Tool calls --%>
              <div :if={Map.get(msg, :tool_calls, []) != []} class="flex flex-col gap-1">
                <div :for={tc <- msg.tool_calls} data-tool={tc.name} class="text-sm text-muted-foreground">
                  {tool_label(tc.name, tc.status)}
                </div>
              </div>

              <%!-- Text content (before spec) --%>
              <div :if={msg.content != ""} class="text-sm leading-relaxed">
                <PhoenixStreamdown.markdown content={msg.content} id={"msg-#{msg.id}"} block_class="mb-3 last:mb-0" />
              </div>

              <%!-- Rendered spec --%>
              <div :if={Map.get(msg, :spec, %{}) != %{}} class="w-full">
                <LiveRender.render spec={msg.spec} catalog={Example.Catalog} id={"spec-#{msg.id}"} />
              </div>

              <%!-- Text content (after spec) --%>
              <div :if={Map.get(msg, :after_content, "") != ""} class="text-sm leading-relaxed">
                <PhoenixStreamdown.markdown content={msg.after_content} id={"msg-after-#{msg.id}"} block_class="mb-3 last:mb-0" />
              </div>
            </div>
          </div>

          <%!-- Currently streaming assistant --%>
          <div :if={@streaming?} class="w-full flex flex-col gap-3">
            <%!-- Active tool calls --%>
            <div :if={@tool_calls != []} class="flex flex-col gap-1">
              <div :for={tc <- @tool_calls} data-tool={tc.name} class="text-sm text-muted-foreground flex items-center gap-1.5">
                <span :if={tc.status == :running} class="inline-block size-3 border-2 border-muted-foreground/40 border-t-transparent rounded-full animate-spin" />
                {tool_label(tc.name, tc.status)}
              </div>
            </div>

            <%!-- Thinking indicator --%>
            <div :if={@current_text == "" and @tool_calls == []} class="text-sm text-muted-foreground animate-pulse">
              Thinking...
            </div>

            <%!-- Streaming text (before spec) --%>
            <div :if={@current_text != ""} class="text-sm leading-relaxed">
              <PhoenixStreamdown.markdown content={strip_spec_fence(@current_text)} streaming animate="fadeIn" id="streaming" block_class="mb-3 last:mb-0" />
            </div>

            <%!-- Streaming spec --%>
            <div :if={@current_spec != %{}} class="w-full">
              <LiveRender.render spec={@current_spec} catalog={Example.Catalog} streaming id="streaming-spec" />
            </div>

            <%!-- Streaming text (after spec) --%>
            <div :if={@after_text != ""} class="text-sm leading-relaxed">
              <PhoenixStreamdown.markdown content={strip_spec_fence(@after_text)} streaming animate="fadeIn" id="streaming-after" block_class="mb-3 last:mb-0" />
            </div>
          </div>

          <%!-- Error display --%>
          <div :if={Phoenix.Flash.get(@flash, :error)} class="rounded-lg border border-destructive/50 bg-destructive/10 px-4 py-3 text-sm text-destructive">
            {Phoenix.Flash.get(@flash, :error)}
          </div>
        </div>
      </main>

      <%!-- Input bar --%>
      <div class="px-6 pb-3 shrink-0 bg-background">
        <.form for={@form} phx-submit="submit" class="max-w-4xl mx-auto relative">
          <input
            type="text"
            name="prompt"
            value={@form[:prompt].value}
            placeholder={if @messages == [], do: "e.g., Compare weather in NYC, London, and Tokyo...", else: "Ask a follow-up..."}
            class="w-full rounded-xl border border-input bg-card px-4 py-3 pr-12 text-sm shadow-sm placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            autocomplete="off"
            autofocus
            disabled={@streaming?}
          />
          <button
            type="submit"
            disabled={@streaming?}
            class="absolute right-3 top-1/2 -translate-y-1/2 h-8 w-8 rounded-lg bg-primary text-primary-foreground flex items-center justify-center hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            <span :if={@streaming?} class="inline-block size-4 border-2 border-primary-foreground border-t-transparent rounded-full animate-spin" />
            <.icon :if={not @streaming?} name="hero-arrow-up" class="size-4" />
          </button>
        </.form>
      </div>
    </div>
    """
  end
end
