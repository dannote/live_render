# LiveRender

Server-driven generative UI for Phoenix LiveView.

AI generates a JSON spec → LiveView resolves it to function components server-side → LiveView diffs only the changed HTML over the WebSocket.

Inspired by Vercel's [json-render](https://github.com/vercel-labs/json-render), built idiomatically for the BEAM.

## Installation

```elixir
def deps do
  [
    {:live_render, "~> 0.1"},
    {:jido_ai, "~> 2.0.0-rc"},   # recommended — agent loop + tool calling
    {:jido_action, "~> 2.0"},     # recommended — typed tool contract
    {:req_llm, "~> 1.6"}          # or use standalone for direct LLM calls
  ]
end
```

## Quick Start

### Render a spec

```heex
<LiveRender.render spec={@spec} catalog={LiveRender.StandardCatalog} streaming={@streaming?} />
```

### With Jido agent + tools (recommended)

Define tools as `Jido.Action` modules:

```elixir
defmodule MyApp.Tools.Weather do
  use Jido.Action,
    name: "get_weather",
    description: "Get weather for a city",
    schema: [city: [type: :string, required: true, doc: "City name"]]

  @impl true
  def run(%{city: city}, _context) do
    # call weather API...
    {:ok, %{temperature: 72, condition: "Sunny"}}
  end
end
```

Run the ReAct agent loop and stream events to your LiveView:

```elixir
def handle_event("ask", %{"prompt" => prompt}, socket) do
  Task.start(fn ->
    config = %{
      model: "anthropic:claude-haiku-4-5",
      system_prompt: MyCatalog.system_prompt(),
      tools: [MyApp.Tools.Weather],
      max_iterations: 5,
      streaming: true
    }

    Jido.AI.Reasoning.ReAct.stream(prompt, config)
    |> Enum.each(fn event ->
      case event.kind do
        :llm_delta -> send(pid, {:live_render, :text_chunk, event.data[:delta]})
        :tool_started -> send(pid, {:live_render, :tool_start, event.tool_name})
        :tool_completed -> send(pid, {:live_render, :tool_done, event.tool_name, event.data[:result]})
        _ -> :ok
      end
    end)
  end)

  {:noreply, assign(socket, streaming?: true)}
end
```

See the [example app](example/) for a complete chat with weather, crypto, GitHub, and Hacker News tools.

### With ReqLLM (standalone)

```elixir
use LiveRender.Live

def handle_event("generate", %{"prompt" => prompt}, socket) do
  LiveRender.Generate.stream_spec("anthropic:claude-haiku-4-5", prompt,
    catalog: LiveRender.StandardCatalog,
    pid: self()
  )

  {:noreply, start_live_render(socket)}
end
```

`use LiveRender.Live` handles all `{:live_render, ...}` messages and provides `init_live_render/1` / `start_live_render/1`.

### Without any LLM dependency

Bring your own client. Feed the spec map to the renderer directly.

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

## Components

Define components with `use LiveRender.Component`:

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

Schemas also support [JSONSpec](https://hex.pm/packages/json_spec):

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

### Built-in components

**Layout:** Stack, Card, Grid, Separator
**Typography:** Heading, Text
**Data:** Metric, Badge, Table, Link
**Interactive:** Button, Tabs, TabContent
**Rich content:** Callout, Timeline, Accordion, Progress, Alert

## Catalog

```elixir
defmodule MyApp.AI.Catalog do
  use LiveRender.Catalog

  component LiveRender.Components.Card
  component LiveRender.Components.Metric
  component MyApp.AI.Components.CustomChart

  action :refresh_data, description: "Refresh all metrics"
end

MyApp.AI.Catalog.system_prompt()   # LLM system prompt with all component schemas
MyApp.AI.Catalog.json_schema()     # JSON Schema for structured output mode
```

## Data Binding

Props reference a state model using expressions:

- `{"$state": "/path/to/value"}` — read from state
- `{"$cond": {"$state": "/flag"}, "$then": "yes", "$else": "no"}` — conditional
- `{"$template": "Hello, ${/user/name}!"}` — string interpolation

## Streaming

Stable elements get `phx-update="ignore"` so LiveView skips them — only the actively streaming element re-renders per chunk.

## Example App

The [example/](example/) directory contains a full chat application porting Vercel's json-render chat example to Phoenix LiveView:

- **Tools** as `Jido.Action` modules: weather (Open-Meteo), crypto (CoinGecko), GitHub, Hacker News
- **Agent** using `Jido.AI.Reasoning.ReAct.stream/3` for the tool loop
- **PhoenixStreamdown** for streaming markdown text
- **LiveRender** for AI-generated dashboard specs

```bash
cd example
cp .env.example .env  # add ANTHROPIC_API_KEY
mix setup
mix phx.server
```

## Development

```bash
mix ci  # compile, format, credo, dialyzer, ex_dna, test
```

## License

MIT
