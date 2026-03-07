# Changelog

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
