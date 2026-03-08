# LiveRender

**Generative UI for Phoenix LiveView.**

AI generates a JSON spec → LiveView resolves it to function components server-side → pushes only HTML diffs over the WebSocket.

Inspired by Vercel's [json-render](https://github.com/vercel-labs/json-render), built idiomatically for the BEAM.

## Why LiveRender?

- **Guardrailed** — AI can only use components you register in a catalog
- **Server-side** — specs stay on the server; no JSON runtime shipped to the client
- **Streaming** — stable elements freeze with `phx-update="ignore"`, only the active node re-renders
- **Progressive** — JSONL patch mode builds the UI element-by-element as the LLM streams
- **Batteries included** — 18 built-in components ready to use
- **Bring your own LLM** — works with ReqLLM, Jido, or any client that produces a spec map

## Quick Start

### 1. Define a catalog

```elixir
defmodule MyApp.AI.Catalog do
  use LiveRender.Catalog

  component LiveRender.Components.Card
  component LiveRender.Components.Metric
  component LiveRender.Components.Button
end
```

`system_prompt/0` generates an LLM prompt describing every registered component — props, types, descriptions. `json_schema/0` returns a JSON Schema for structured output.

### 2. Render a spec

```heex
<LiveRender.render
  spec={@spec}
  catalog={MyApp.AI.Catalog}
  streaming={@streaming?}
/>
```

**That's it.** AI generates JSON, LiveRender renders it safely through your catalog.

### 3. Connect an LLM

With [ReqLLM](https://hex.pm/packages/req_llm):

```elixir
defmodule MyAppWeb.DashboardLive do
  use MyAppWeb, :live_view
  use LiveRender.Live

  def mount(_params, _session, socket), do: {:ok, init_live_render(socket)}

  def handle_event("generate", %{"prompt" => prompt}, socket) do
    LiveRender.Generate.stream_spec("anthropic:claude-haiku-4-5", prompt,
      catalog: MyApp.AI.Catalog,
      pid: self()
    )

    {:noreply, start_live_render(socket)}
  end
end
```

`use LiveRender.Live` injects `handle_info` clauses for `:text_chunk`, `:spec`, `:done`, and `:error` messages.

Or with [Jido](https://hex.pm/packages/jido_ai) for full ReAct agent loops with tool calling — see the [example app](example/).

Or bring your own client — anything that produces a spec map works.

## Installation

```elixir
def deps do
  [
    {:live_render, "~> 0.2"}
  ]
end
```

Optional dependencies unlock extra features:

| Dependency | Unlocks |
|---|---|
| `{:req_llm, "~> 1.6"}` | `LiveRender.Generate` — streaming/one-shot spec generation |
| `{:nimble_options, "~> 1.0"}` | Keyword list schema validation with defaults and coercion |
| `{:json_spec, "~> 1.1"}` | Elixir typespec-style schemas that compile to JSON Schema |

## Spec Format

### Object mode (default)

```json
{
  "root": "card-1",
  "state": { "temperature": 72 },
  "elements": {
    "card-1": {
      "type": "card",
      "props": { "title": "Weather" },
      "children": ["metric-1"]
    },
    "metric-1": {
      "type": "metric",
      "props": {
        "label": "Temperature",
        "value": { "$state": "/temperature" }
      },
      "children": []
    }
  }
}
```

### Patch mode (progressive streaming)

Use `system_prompt(mode: :patch)` to instruct the LLM to output RFC 6902 JSONL patches. Each line adds or modifies a part of the spec, so the UI fills in progressively:

    ```spec
    {"op":"add","path":"/root","value":"main"}
    {"op":"add","path":"/elements/main","value":{"type":"stack","props":{},"children":["m1"]}}
    {"op":"add","path":"/elements/m1","value":{"type":"metric","props":{"label":"Users","value":"1,234"},"children":[]}}
    ```

Apply patches with `LiveRender.SpecPatch.parse_and_apply/2`. Supports `add`, `replace`, `remove`, and the `-` array append operator for streaming table rows.

## Custom Components

```elixir
defmodule MyApp.AI.Components.PriceCard do
  use LiveRender.Component,
    name: "price_card",
    description: "Displays a price with currency formatting",
    schema: [
      label: [type: :string, required: true, doc: "Item name"],
      price: [type: :float, required: true, doc: "Price value"],
      currency: [type: {:in, [:usd, :eur, :gbp]}, default: :usd, doc: "Currency"]
    ]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div class="rounded-lg border border-border p-4">
      <span class="text-sm text-muted-foreground"><%= @label %></span>
      <span class="text-2xl font-bold"><%= symbol(@currency) %><%= :erlang.float_to_binary(@price, decimals: 2) %></span>
    </div>
    """
  end

  defp symbol(:usd), do: "$"
  defp symbol(:eur), do: "€"
  defp symbol(:gbp), do: "£"
end
```

Register it:

```elixir
defmodule MyApp.AI.Catalog do
  use LiveRender.Catalog

  component MyApp.AI.Components.PriceCard
  component LiveRender.Components.Card
  component LiveRender.Components.Stack

  action :add_to_cart, description: "Add an item to the shopping cart"
end
```

Schemas support [NimbleOptions](https://hex.pm/packages/nimble_options) keyword lists, [JSONSpec](https://hex.pm/packages/json_spec) maps, or raw JSON Schema.

## Data Binding

Any prop value can be an expression resolved against the spec's `state`:

```json
{ "$state": "/user/name" }
{ "$cond": { "$state": "/loggedIn" }, "$then": "Welcome!", "$else": "Sign in" }
{ "$template": "Hello, ${/user/name}!" }
{ "$concat": ["Humidity: ", { "$state": "/humidity" }, "%"] }
```

## Styling

Built-in components use CSS variable-based classes compatible with [shadcn/ui](https://ui.shadcn.com/) theming (`text-muted-foreground`, `bg-card`, `border-border`, `bg-primary`, etc.). Define these variables in your app's CSS to control colors in both light and dark mode.

## Hooks

The Tabs component requires a `LiveRenderTabs` hook. Register it in your `app.js`:

```javascript
const LiveRenderTabs = {
  mounted() {
    this.el.addEventListener("lr:tab-change", () => {
      const active = this.el.dataset.active;
      this.el.querySelectorAll("[data-tab-value]").forEach(btn => {
        btn.dataset.state = btn.dataset.tabValue === active ? "active" : "inactive";
      });
      this.el.querySelectorAll("[data-tab-content]").forEach(panel => {
        panel.dataset.state = panel.dataset.tabContent === active ? "active" : "inactive";
      });
    });
    this.el.dispatchEvent(new Event("lr:tab-change"));
  }
};

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: { LiveRenderTabs }
});
```

## Built-in Components

| Category | Components |
|---|---|
| **Layout** | Stack, Card, Grid, Separator |
| **Typography** | Heading, Text |
| **Data** | Metric, Badge, Table, Link |
| **Interactive** | Button, Tabs, TabContent |
| **Rich** | Callout, Timeline, Accordion, Progress, Alert |

Use them directly with `LiveRender.StandardCatalog`, or pick individual ones for your own catalog.

## Tools

With ReqLLM:

```elixir
LiveRender.Generate.stream_spec(model, prompt,
  catalog: MyApp.AI.Catalog,
  pid: self(),
  tools: [
    LiveRender.Tool.new!(
      name: "get_weather",
      description: "Get current weather",
      parameter_schema: [location: [type: :string, required: true, doc: "City"]],
      callback: &MyApp.Weather.fetch/1
    )
  ]
)
```

With Jido, define tools as `Jido.Action` modules for a full ReAct agent loop.

## Example App

The [`example/`](example/) directory contains a chat application porting Vercel's json-render chat example:

- Tools: weather, crypto, GitHub, Hacker News
- Jido ReAct agent with JSONL patch streaming
- PhoenixStreamdown for streaming markdown with word-level animations
- OpenRouter and Anthropic support

```bash
cd example
cp .env.example .env  # add your API key (Anthropic or OpenRouter)
mix setup
mix phx.server
```

## Development

```bash
mix ci  # compile, format, credo, dialyzer, ex_dna, test
```

## License

MIT — see [LICENSE](LICENSE).
