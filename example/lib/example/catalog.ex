defmodule Example.Catalog do
  use LiveRender.Catalog

  # Layout
  component LiveRender.Components.Stack
  component LiveRender.Components.Card
  component LiveRender.Components.Grid
  component LiveRender.Components.Separator

  # Typography
  component LiveRender.Components.Heading
  component LiveRender.Components.Text

  # Data display
  component LiveRender.Components.Metric
  component LiveRender.Components.Badge
  component LiveRender.Components.Table
  component LiveRender.Components.Link

  # Interactive
  component LiveRender.Components.Button
  component LiveRender.Components.Tabs
  component LiveRender.Components.TabContent

  # Rich content
  component LiveRender.Components.Callout
  component LiveRender.Components.Timeline
  component LiveRender.Components.Accordion
  component LiveRender.Components.Progress
  component LiveRender.Components.Alert

  action :set_state, description: "Set a value at a state path"
end
