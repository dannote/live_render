defmodule LiveRender.Live do
  @moduledoc """
  LiveView helpers for integrating with `LiveRender.Generate`.

  Provides `use LiveRender.Live` to set up assigns and message handling
  for streaming AI-generated specs.

  ## Usage

      defmodule MyAppWeb.DashboardLive do
        use MyAppWeb, :live_view
        use LiveRender.Live

        @impl true
        def mount(_params, _session, socket) do
          {:ok, init_live_render(socket)}
        end

        @impl true
        def render(assigns) do
          ~H\"\"\"
          <form phx-submit="generate">
            <input type="text" name="prompt" />
          </form>

          <.markdown :if={@lr_text != ""} content={@lr_text} streaming={@lr_streaming?} />
          <LiveRender.render :if={@lr_spec != %{}} spec={@lr_spec} catalog={MyApp.AI.Catalog} streaming={@lr_streaming?} />
          \"\"\"
        end

        @impl true
        def handle_event("generate", %{"prompt" => prompt}, socket) do
          LiveRender.Generate.stream_spec("anthropic:claude-haiku-4-5", prompt,
            catalog: MyApp.AI.Catalog,
            pid: self()
          )

          {:noreply, start_live_render(socket)}
        end
      end
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import LiveRender.Live, only: [init_live_render: 1, start_live_render: 1]

      @impl true
      def handle_info({:live_render, :text_chunk, token}, socket) do
        {:noreply, assign(socket, :lr_text, socket.assigns.lr_text <> token)}
      end

      @impl true
      def handle_info({:live_render, :spec, spec}, socket) do
        {:noreply, assign(socket, :lr_spec, spec)}
      end

      @impl true
      def handle_info({:live_render, :done, _response}, socket) do
        {:noreply, assign(socket, :lr_streaming?, false)}
      end

      @impl true
      def handle_info({:live_render, :error, reason}, socket) do
        {:noreply,
         socket
         |> assign(:lr_streaming?, false)
         |> Phoenix.LiveView.put_flash(:error, "Generation error: #{inspect(reason)}")}
      end

      defoverridable handle_info: 2
    end
  end

  @doc "Initializes LiveRender assigns on a socket."
  def init_live_render(socket) do
    Phoenix.Component.assign(socket, %{
      lr_spec: %{},
      lr_text: "",
      lr_streaming?: false
    })
  end

  @doc "Resets LiveRender assigns for a new generation."
  def start_live_render(socket) do
    Phoenix.Component.assign(socket, %{
      lr_spec: %{},
      lr_text: "",
      lr_streaming?: true
    })
  end
end
