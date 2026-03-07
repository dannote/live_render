# LiveRender

Server-driven generative UI for Phoenix LiveView.

AI generates a JSON spec → LiveView resolves it to function components server-side → LiveView diffs only the changed HTML over the WebSocket.

## Installation

```elixir
def deps do
  [
    {:live_render, "~> 0.1"},
    {:req_llm, "~> 1.6"}     # optional — for LLM integration
  ]
end
```

## Quick Start

### With ReqLLM (recommended)

```elixir
defmodule MyAppWeb.DashboardLive do
  use MyAppWeb, :live_view
  use LiveRender.Live

  @impl true
  def mount(_params, _session, socket) do
    {:ok, init_live_render(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <form phx-submit="generate">
      <input type="text" name="prompt" placeholder="Describe a dashboard..." />
      <button type="submit">Generate</button>
    </form>

    <div :if={@lr_text != ""} class="prose"><%= @lr_text %></div>

    <LiveRender.render
      :if={@lr_spec != %{}}
      spec={@lr_spec}
      catalog={LiveRender.StandardCatalog}
      streaming={@lr_streaming?}
    />
    """
  end

  @impl true
  def handle_event("generate", %{"prompt" => prompt}, socket) do
    LiveRender.Generate.stream_spec("anthropic:claude-haiku-4-5", prompt,
      catalog: LiveRender.StandardCatalog,
      pid: self()
    )

    {:noreply, start_live_render(socket)}
  end
end
```

`use LiveRender.Live` sets up `handle_info` clauses for all `{:live_render, ...}` messages
and provides `init_live_render/1` / `start_live_render/1` helpers.

### With tools

```elixir
tools = [
  LiveRender.Tool.new!(
    name: "get_weather",
    description: "Get current weather for a location",
    parameter_schema: [
      location: [type: :string, required: true, doc: "City name"]
    ],
    callback: fn args -> {:ok, Weather.fetch(args[:location])} end
  )
]

LiveRender.Generate.stream_spec("anthropic:claude-haiku-4-5", prompt,
  catalog: MyApp.AI.Catalog,
  pid: self(),
  tools: tools
)
```

`LiveRender.Tool` delegates to `ReqLLM.Tool` — all schema formats work: NimbleOptions keyword lists, JSONSpec maps, or raw JSON Schema.

### Without ReqLLM

Bring your own LLM client. Feed the spec map to the renderer:

```heex
<LiveRender.render spec={@spec} catalog={LiveRender.StandardCatalog} streaming={@streaming?} />
```

## Spec Format

```json
{
  "root": "card-1",
  "state": {"temperature": 72},
  "elements": {
    "card-1": {
      "type": "card",
      "props": {"title": "Weather"},
      "children": ["metric-1"]
    },
    "metric-1": {
      "type": "metric",
      "props": {"label": "Temperature", "value": {"$state": "/temperature"}},
      "children": []
    }
  }
}
```

## Custom Components

```elixir
defmodule MyApp.AI.Components.Metric do
  use LiveRender.Component,
    name: "metric",
    description: "Display a single metric value",
    schema: [
      label: [type: :string, required: true, doc: "Metric label"],
      value: [type: :string, required: true, doc: "Display value"],
      trend: [type: {:in, [:up, :down, :neutral]}, doc: "Trend direction"]
    ]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div class="flex flex-col">
      <span class="text-sm text-gray-500"><%= @label %></span>
      <span class="text-2xl font-bold"><%= @value %></span>
    </div>
    """
  end
end
```

Schemas also support [JSONSpec](https://hex.pm/packages/json_spec) syntax:

```elixir
import JSONSpec

use LiveRender.Component,
  name: "metric",
  description: "Display a single metric value",
  schema: schema(
    %{required(:label) => String.t(), required(:value) => String.t()},
    doc: [label: "Metric label", value: "Display value"]
  )
```

## Custom Catalog

```elixir
defmodule MyApp.AI.Catalog do
  use LiveRender.Catalog

  component LiveRender.Components.Card
  component LiveRender.Components.Metric
  component MyApp.AI.Components.CustomChart

  action :refresh_data, description: "Refresh all metrics"
end
```

Generate a system prompt from your catalog:

```elixir
MyApp.AI.Catalog.system_prompt()
```

The prompt describes all registered components with their props, types, and
descriptions — ready to embed in an LLM call. `json_schema/0` returns a
JSON Schema for structured output mode.

## Data Binding

Props can reference a state model using expressions:

- `{"$state": "/path/to/value"}` — read from state
- `{"$cond": {"$state": "/flag"}, "$then": "yes", "$else": "no"}` — conditional
- `{"$template": "Hello, ${/user/name}!"}` — string interpolation

## Streaming

During LLM streaming, stable elements get `phx-update="ignore"` so LiveView skips them — only the last element re-renders per chunk.

When using `LiveRender.Generate`, text chunks arrive as `{:live_render, :text_chunk, token}` and the final parsed spec arrives as `{:live_render, :spec, spec}`. Use `LiveRender.Live` to handle these automatically, or pattern-match them yourself.

## Built-in Components

**Layout:** Stack, Card, Grid, Separator
**Typography:** Heading, Text
**Data:** Metric, Badge, Table, Link
**Interactive:** Button, Tabs, TabContent
**Rich content:** Callout, Timeline, Accordion, Progress, Alert

## License

MIT
