# LiveRender

Server-driven generative UI for Phoenix LiveView.

AI generates a JSON spec → LiveView resolves it to function components server-side → LiveView diffs only the changed HTML over the WebSocket.

## Installation

```elixir
def deps do
  [{:live_render, "~> 0.1"}]
end
```

## Quick Start

```heex
<LiveRender.render spec={@spec} catalog={LiveRender.StandardCatalog} streaming={@streaming?} />
```

The spec is a JSON map:

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

Generate an LLM system prompt from your catalog:

```elixir
MyApp.AI.Catalog.system_prompt()
```

## Data Binding

Props can reference a state model using expressions:

- `{"$state": "/path/to/value"}` — read from state
- `{"$cond": {"$state": "/flag"}, "$then": "yes", "$else": "no"}` — conditional
- `{"$template": "Hello, ${/user/name}!"}` — string interpolation

## Streaming

During LLM streaming, stable elements get `phx-update="ignore"` so LiveView skips them — only the last element re-renders per chunk.

```elixir
def handle_info({:spec_chunk, chunk}, socket) do
  spec = deep_merge(socket.assigns.spec, chunk)
  {:noreply, assign(socket, spec: spec)}
end
```

## Built-in Components

**Layout:** Stack, Card, Grid, Separator
**Typography:** Heading, Text
**Data:** Metric, Badge, Table, Link
**Interactive:** Button, Tabs, TabContent
**Rich content:** Callout, Timeline, Accordion, Progress, Alert

## License

MIT
