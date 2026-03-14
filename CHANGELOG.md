# Changelog

## 0.5.0 (2026-03-14)

### Features

- **`LiveRender.Format.YAML`** — YAML wire format with progressive streaming. The LLM outputs YAML inside a code fence (`` ```spec `` or `` ```yaml ``), and the streaming parser incrementally re-parses on each newline, emitting `{:spec, spec}` events as the structure grows. Requires `{:yaml_elixir, "~> 2.12"}` (optional dependency).
- **Merge edit mode** — multi-turn spec refinement via RFC 7396 JSON Merge Patch. Pass `:current_spec` to `Generate.stream_spec/3` or any format's prompt/parse/stream_init opts, and the LLM outputs only changed keys which are deep-merged into the existing spec. Supported by JSONPatch (via `__lr_edit` flag), JSONObject, and YAML formats.
- **`LiveRender.SpecMerge`** — RFC 7396 deep merge: `nil` deletes keys, arrays replace atomically, maps recurse.
- **Shared fence extraction** — `Shared.extract_fence/2` replaces duplicated regex across all five formats with a single `String.split`-based function that accepts a list of fence markers.

### Fixes

- **YAML streaming spec validation** — only emit specs where `root` is a string, `elements` is a non-empty map, every element value is a map with a string `type`, and `props` is a map or nil. Prevents crashes from intermediate YAML parse states like `%{"main" => "type"}`.
- **Renderer defensive guards** — `get_node` returns nil for non-map element values; `children` coerced to `[]` when not a list; `props` coerced to `%{}` when not a map.
- **List prop sanitization** — `sanitize_list_props` filters non-map items from `{:list, :map}` schema props after validation, preventing crashes when YAML streaming produces intermediate list values like `["value"]` instead of `[%{"value" => "..."}]`.
- **Component nil guards** — Tabs, Timeline, Accordion, and Table all guard against nil list props (`tabs`, `items`, `columns`) during streaming.

## 0.4.0 (2026-03-12)

### Features

- **`LiveRender.Format.A2UI`** — adapter for Google's [A2UI protocol](https://github.com/google/A2UI). Consumes A2UI JSONL envelope messages (`createSurface`, `updateComponents`, `updateDataModel`, `deleteSurface`) and translates them to LiveRender specs. Supports progressive streaming, automatic PascalCase→snake_case component mapping, and conversion of A2UI data bindings (`{"path": "/..."}`) to LiveRender's `{"$state": "/..."}` expressions. Works with A2UI agents over A2A, AG UI, MCP, WebSockets, or any transport.

## 0.3.0 (2026-03-11)

### Features

- **`LiveRender.Format` behaviour** — pluggable spec format backends with 5 callbacks: `prompt/3`, `parse/2`, `stream_init/1`, `stream_push/2`, `stream_flush/1`
- **`LiveRender.Format.JSONPatch`** — extracted from `SpecPatch` + `Builder`; JSONL RFC 6902 patches for progressive streaming
- **`LiveRender.Format.JSONObject`** — extracted from `JSONRepair` + `Builder`; single JSON object format
- **`LiveRender.Format.OpenUILang`** — compact line-oriented DSL that uses ~50% fewer tokens than JSON. Includes `Tokenizer`, `Parser` (recursive descent), and `Compiler` (AST → spec map) sub-modules
- **Shared streaming helpers** — fence detection, backtick holding, and line splitting extracted to eliminate duplication across all three formats
- **`prop_order/0` on components** — deterministic positional argument mapping for OpenUI Lang, derived from schema key order
- **Type hints in OpenUI Lang signatures** — prompt shows valid enum values: `Heading(text, level?: "h1"|"h2"|"h3"|"h4")`
- **`format:` option** for `system_prompt/1`, `Generate.stream_spec/3`, and `Generate.generate_spec/3`

### Fixes

- **Invalid enum prop crash** — when the LLM outputs an invalid value for an `{:in, values}` prop (e.g., integer `1` instead of `"h1"`), the renderer falls back to the schema default instead of crashing

### Migration

- The `mode: :patch` and `mode: :object` options continue to work and map to `LiveRender.Format.JSONPatch` and `LiveRender.Format.JSONObject` respectively
- Default format remains `LiveRender.Format.JSONPatch` — no changes needed for existing code

## 0.2.1 (2026-03-08)

- Update README: installation version, patch mode docs, `$concat`, hooks, styling section, example app instructions

## 0.2.0 (2026-03-08)

### Features

- **`LiveRender.SpecPatch`** — RFC 6902 JSON Patch for progressive streaming. Apply `add`, `replace`, `remove` operations to build specs incrementally as the LLM streams. Supports `-` array append and numeric list indices.
- **`LiveRender.JSONRepair`** — repairs truncated JSON from streaming (closes open strings, strips trailing syntax, closes unmatched brackets)
- **`$concat` expression** — `{"$concat": ["Humidity: ", {"$state": "/humidity"}, "%"]}` concatenates resolved parts into a string
- **Patch mode for catalog prompts** — `LiveRender.Catalog.Builder.system_prompt(mode: :patch)` generates instructions for JSONL patch output instead of a single JSON object
- **Card `description` prop** — optional subtitle text below the title
- **Alert `title` prop** — optional heading inside alerts
- **Text `variant` prop** — `:default`, `:muted`, `:caption`, `:lead`, `:code` variants replace the boolean `muted` prop
- **Text `text` prop** — alias for `content`, matching the naming convention used by LLMs
- **Link `label` prop** — alias for `text`
- **Separator `orientation` prop** — `:horizontal` (default) or `:vertical`
- **Grid columns 5–6** — `columns_class` now handles 5 and 6 column layouts

### Fixes

- **Empty slot crash** — components declaring `:inner_block` but receiving no children no longer raise `KeyError`; they get an empty slot
- **Schema defaults on validation failure** — when props fail validation, schema defaults are still applied instead of leaving atoms as `nil`
- **Streaming re-render** — `__changed__` now includes all component assign keys during streaming so LiveView re-diffs every prop
- **Table with non-list data** — `data` prop coerced to `[]` when not a list (prevents crashes during progressive streaming before state is populated)
- **Table string-keyed maps** — `col_value/2` checks both string and atom keys so headers and cells render correctly with LLM-generated string-keyed data
- **Metric nil value** — `display_value(nil)` returns `""` instead of crashing
- **Progress string values** — `parse_value/1` handles string percentages like `"75%"`
- **Stack/Grid gap classes** — use explicit Tailwind classes (`gap-0` through `gap-8`) instead of string interpolation which Tailwind can't scan

### Breaking changes

- **Tabs no longer require Alpine.js** — rewritten to use `phx-hook="LiveRenderTabs"` + `data-state` attributes + `Phoenix.LiveView.JS`. Consumers must register the `LiveRenderTabs` hook.
- **Text `muted` prop removed** — replaced by `variant: :muted`
- **Progress `color` prop removed** — uses CSS variable-based theming
- **Card `variant` prop no longer affects styling** — uses shadcn-style border/shadow card layout

### Styling

- All components migrated from hardcoded `gray-*` / `dark:gray-*` classes to CSS variable-based theming (`text-muted-foreground`, `bg-card`, `border-border`, etc.) compatible with shadcn/ui
- Button variants use `bg-primary`, `bg-secondary`, `bg-destructive` CSS variables
- Progress bar uses `translateX` transform matching shadcn's Progress component
- Card uses `rounded-xl border shadow-sm` with header/content sections

## 0.1.0 (2026-03-08)

Initial release.

- Spec renderer with streaming support (`phx-update="ignore"` on stable nodes)
- 18 built-in components: Stack, Card, Grid, Separator, Heading, Text, Metric, Badge, Table, Link, Button, Tabs, TabContent, Callout, Timeline, Accordion, Progress, Alert
- Catalog system with `system_prompt/0` and `json_schema/0` for LLM integration
- `StateResolver` — `$state`, `$bindState`, `$cond`, `$template` expressions
- `SchemaAdapter` — NimbleOptions, JSONSpec, and raw JSON Schema support
- `LiveRender.Generate` — streaming/one-shot spec generation via ReqLLM (optional)
- `LiveRender.Live` — `use` macro with `handle_info` handlers and socket helpers
- `LiveRender.Tool` — convenience wrapper for `ReqLLM.Tool` (optional)
- `StandardCatalog` — all built-in components pre-registered
