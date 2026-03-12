# LiveRender

**Generative UI for Phoenix LiveView.**

AI generates a UI spec → LiveView resolves it to function components server-side → pushes only HTML diffs over the WebSocket.

Inspired by Vercel's [json-render](https://github.com/vercel-labs/json-render), built idiomatically for the BEAM.

## Why LiveRender?

- **Guardrailed** — AI can only use components you register in a catalog
- **Server-side** — specs stay on the server; no JSON runtime shipped to the client
- **Streaming** — stable elements freeze with `phx-update="ignore"`, only the active node re-renders
- **Progressive** — patch mode builds the UI element-by-element as the LLM streams
- **Multi-format** — JSON patches, JSON objects, or [OpenUI Lang](#openui-lang) (~50% fewer tokens)
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

`system_prompt/1` generates an LLM prompt describing every registered component — props, types, descriptions. `json_schema/0` returns a JSON Schema for structured output.

### 2. Render a spec

```heex
<LiveRender.render
  spec={@spec}
  catalog={MyApp.AI.Catalog}
  streaming={@streaming?}
/>
```

**That's it.** AI generates the spec, LiveRender renders it safely through your catalog.

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
    {:live_render, "~> 0.3"}
  ]
end
```

Optional dependencies unlock extra features:

| Dependency | Unlocks |
|---|---|
| `{:req_llm, "~> 1.6"}` | `LiveRender.Generate` — streaming/one-shot spec generation |
| `{:nimble_options, "~> 1.0"}` | Keyword list schema validation with defaults and coercion |
| `{:json_spec, "~> 1.1"}` | Elixir typespec-style schemas that compile to JSON Schema |

## Formats

LiveRender supports multiple spec formats through the `LiveRender.Format` behaviour. Each format defines how the LLM encodes UI specs, how to parse responses, and how to handle streaming.

| Format | Module | Token cost | Best for |
|---|---|---|---|
| **JSON Patch** | `LiveRender.Format.JSONPatch` | High | Progressive streaming — UI appears element-by-element |
| **JSON Object** | `LiveRender.Format.JSONObject` | High | Simple one-shot generation |
| **OpenUI Lang** | `LiveRender.Format.OpenUILang` | **~50% less** | Token-sensitive workloads, fast models |
| **A2UI** | `LiveRender.Format.A2UI` | High | Interop with [A2UI](https://github.com/google/A2UI) agents and transports |

Pass `:format` to `system_prompt/1` or `stream_spec/3`:

```elixir
# In catalog prompts
MyApp.AI.Catalog.system_prompt(format: LiveRender.Format.OpenUILang)

# In Generate
LiveRender.Generate.stream_spec(model, prompt,
  catalog: MyApp.AI.Catalog,
  pid: self(),
  format: LiveRender.Format.OpenUILang
)
```

The legacy `mode: :patch` / `mode: :object` options still work and map to the corresponding format modules.

### JSON Patch (default)

The LLM outputs RFC 6902 JSONL patches inside a `` ```spec `` fence. Each line adds or modifies a part of the spec, so the UI fills in progressively:

    ```spec
    {"op":"add","path":"/root","value":"main"}
    {"op":"add","path":"/elements/main","value":{"type":"stack","props":{},"children":["m1"]}}
    {"op":"add","path":"/elements/m1","value":{"type":"metric","props":{"label":"Users","value":"1,234"},"children":[]}}
    ```

Supports `add`, `replace`, `remove`, and the `-` array append operator for streaming table rows.

### JSON Object

The LLM outputs a single JSON object:

    ```spec
    {
      "root": "card-1",
      "elements": {
        "card-1": { "type": "card", "props": { "title": "Stats" }, "children": ["m1"] },
        "m1": { "type": "metric", "props": { "label": "Users", "value": "1,234" }, "children": [] }
      }
    }
    ```

### OpenUI Lang

A compact line-oriented DSL that uses ~50% fewer tokens than JSON. The LLM outputs positional component calls:

    ```spec
    root = Stack([heading, grid])
    heading = Heading("Weather Dashboard")
    grid = Grid([nyCard, londonCard], 2)
    nyCard = Card([nyTemp, nyWind], "New York")
    nyTemp = Metric("Temperature", "72°F")
    nyWind = Metric("Wind", "8 mph")
    londonCard = Card([londonTemp], "London")
    londonTemp = Metric("Temperature", "15°C")
    ```

**Syntax:**

| Construct | Example |
|---|---|
| Assignment | `id = Expression` |
| Component | `TypeName(arg1, arg2, ...)` |
| String | `"text"` |
| Number | `42`, `3.14`, `-1` |
| Boolean | `true` / `false` |
| Null | `null` |
| Array | `[a, b, c]` |
| Object | `{key: value}` |
| Reference | `identifier` (refers to another assignment) |

Arguments are positional, mapped to props by the component's schema key order. The prompt auto-generates signatures with type hints so the LLM knows valid values:

```
- Heading(text, level?: "h1"|"h2"|"h3"|"h4") — Section heading
- Card(children, title?, description?, variant?: "default"|"bordered"|"shadow") — A card container
- Metric(label, value, detail?, trend?: "up"|"down"|"neutral") — Single metric display
```

OpenUI Lang compiles to the same spec map as JSON formats — the renderer doesn't care which format produced the spec.

### A2UI

Google's [A2UI protocol](https://github.com/google/A2UI) — a JSONL stream of envelope messages (`createSurface`, `updateComponents`, `updateDataModel`, `deleteSurface`). Use this format to consume UI from A2UI-speaking agents over A2A, AG UI, MCP, or any other transport.

    ```spec
    {"version":"v0.10","createSurface":{"surfaceId":"main","catalogId":"basic"}}
    {"version":"v0.10","updateComponents":{"surfaceId":"main","components":[{"id":"root","component":"Stack","children":["heading","metric1"]},{"id":"heading","component":"Heading","text":"Dashboard"},{"id":"metric1","component":"Metric","label":"Users","value":{"path":"/users/count"}}]}}
    {"version":"v0.10","updateDataModel":{"surfaceId":"main","path":"/users","value":{"count":"1,234"}}}
    ```

A2UI data bindings (`{"path": "/..."}`) are automatically converted to LiveRender's `{"$state": "/..."}` expressions. Component names use PascalCase and are mapped to catalog entries via snake_case conversion.

### Custom Formats

Implement the `LiveRender.Format` behaviour to add your own:

```elixir
defmodule MyApp.Format.YAML do
  @behaviour LiveRender.Format

  @impl true
  def prompt(component_map, actions, opts), do: "..."

  @impl true
  def parse(text, opts), do: {:ok, %{}}

  @impl true
  def stream_init(opts), do: %{}

  @impl true
  def stream_push(state, chunk), do: {state, []}

  @impl true
  def stream_flush(state), do: {state, []}
end
```

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

The [`example/`](example/) directory contains a chat application:

- Tools: weather, crypto, GitHub, Hacker News
- Jido ReAct agent with streaming
- Configurable format (OpenUI Lang by default in dev)
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
