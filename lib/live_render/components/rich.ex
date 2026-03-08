defmodule LiveRender.Components.Callout do
  use LiveRender.Component,
    name: "callout",
    description: "Highlighted callout box for tips, warnings, notes, or key information",
    schema: [
      type: [
        type: {:in, [:info, :tip, :warning, :important]},
        default: :info,
        doc: "Callout type"
      ],
      title: [type: :string, doc: "Callout title"],
      content: [type: :string, required: true, doc: "Callout body text"]
    ]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div class={["border-l-4 rounded-r-lg p-4", callout_class(@type)]}>
      <div class="flex items-start gap-3">
        <span class="text-lg shrink-0"><%= callout_icon(@type) %></span>
        <div>
          <p :if={@title} class="font-semibold text-sm mb-1"><%= @title %></p>
          <p class="text-sm text-muted-foreground"><%= @content %></p>
        </div>
      </div>
    </div>
    """
  end

  defp callout_class(:info), do: "border-blue-500 bg-blue-50 dark:bg-blue-950/50"
  defp callout_class(:tip), do: "border-emerald-500 bg-emerald-50 dark:bg-emerald-950/50"
  defp callout_class(:warning), do: "border-amber-500 bg-amber-50 dark:bg-amber-950/50"
  defp callout_class(:important), do: "border-purple-500 bg-purple-50 dark:bg-purple-950/50"

  defp callout_icon(:info), do: "ℹ️"
  defp callout_icon(:tip), do: "💡"
  defp callout_icon(:warning), do: "⚠️"
  defp callout_icon(:important), do: "⭐"
end

defmodule LiveRender.Components.Timeline do
  use LiveRender.Component,
    name: "timeline",
    description: "Vertical timeline showing ordered events, steps, or milestones",
    schema: [
      items: [
        type: {:list, :map},
        required: true,
        doc:
          "List of items with title, description (optional), date (optional), status (optional: completed | current | upcoming)"
      ]
    ]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div class="relative pl-8">
      <div class="absolute left-[5.5px] top-3 bottom-3 w-px bg-border" />
      <div class="flex flex-col gap-6">
        <div :for={item <- @items} class="relative">
          <div class={["absolute -left-8 top-0.5 h-3 w-3 rounded-full ring-2 ring-background", dot_class(item["status"])]}>
          </div>
          <div>
            <div class="flex items-center gap-2 flex-wrap">
              <p class="font-medium text-sm"><%= item["title"] %></p>
              <span :if={item["date"]} class="text-xs text-muted-foreground bg-muted px-1.5 py-0.5 rounded">
                <%= item["date"] %>
              </span>
            </div>
            <p :if={item["description"]} class="text-sm text-muted-foreground mt-1">
              <%= item["description"] %>
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp dot_class("completed"), do: "bg-emerald-500"
  defp dot_class("current"), do: "bg-blue-500"
  defp dot_class("upcoming"), do: "bg-muted-foreground/30"
  defp dot_class(_), do: "bg-muted-foreground"
end

defmodule LiveRender.Components.Accordion do
  use LiveRender.Component,
    name: "accordion",
    description: "Expandable sections for organizing detailed content",
    schema: [
      items: [
        type: {:list, :map},
        required: true,
        doc: "List of items with title and content"
      ]
    ]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div class="w-full">
      <details :for={item <- @items} class="group border-b border-border">
        <summary class="flex items-center justify-between py-4 cursor-pointer text-sm font-medium hover:underline [&::-webkit-details-marker]:hidden">
          <%= item["title"] %>
          <span class="text-muted-foreground group-open:rotate-180 transition-transform text-xs">▼</span>
        </summary>
        <div class="pb-4 text-sm text-muted-foreground">
          <%= item["content"] %>
        </div>
      </details>
    </div>
    """
  end
end

defmodule LiveRender.Components.Progress do
  use LiveRender.Component,
    name: "progress",
    description: "Progress bar",
    schema: [
      value: [type: :integer, required: true, doc: "Current value (0-100)"],
      label: [type: :string, doc: "Label text"]
    ]

  use Phoenix.Component

  def render(assigns) do
    pct = min(max(parse_value(assigns[:value]), 0), 100)
    assigns = assign(assigns, :pct, pct)

    ~H"""
    <div class="space-y-2">
      <div :if={@label} class="flex justify-between text-sm">
        <span class="text-muted-foreground"><%= @label %></span>
        <span class="text-muted-foreground"><%= @pct %>%</span>
      </div>
      <div class="bg-primary/20 relative h-2 w-full overflow-hidden rounded-full">
        <div
          class="bg-primary h-full w-full flex-1 transition-all"
          style={"transform: translateX(-#{100 - @pct}%)"}
        >
        </div>
      </div>
    </div>
    """
  end

  defp parse_value(v) when is_integer(v), do: v
  defp parse_value(v) when is_float(v), do: round(v)
  defp parse_value(v) when is_binary(v) do
    case Float.parse(v) do
      {n, _} -> round(n)
      :error -> 0
    end
  end
  defp parse_value(_), do: 0
end

defmodule LiveRender.Components.Alert do
  use LiveRender.Component,
    name: "alert",
    description: "Alert message",
    schema: [
      title: [type: :string, doc: "Alert title"],
      message: [type: :string, required: true, doc: "Alert message"],
      variant: [
        type: {:in, [:info, :success, :warning, :error]},
        default: :info,
        doc: "Alert type"
      ]
    ]

  use Phoenix.Component

  def render(assigns) do
    assigns = assign_new(assigns, :title, fn -> nil end)

    ~H"""
    <div role="alert" class={["relative w-full rounded-lg border p-4 text-sm", alert_class(@variant)]}>
      <h5 :if={@title} class="mb-1 font-medium leading-none tracking-tight"><%= @title %></h5>
      <div class="text-sm [&_p]:leading-relaxed"><%= @message %></div>
    </div>
    """
  end

  defp alert_class(:success),
    do: "border-green-200 bg-green-50 text-green-900 dark:border-green-800 dark:bg-green-950 dark:text-green-100"

  defp alert_class(:warning),
    do: "border-yellow-200 bg-yellow-50 text-yellow-900 dark:border-yellow-800 dark:bg-yellow-950 dark:text-yellow-100"

  defp alert_class(:error),
    do: "border-destructive/50 bg-destructive/10 text-destructive"

  defp alert_class(_),
    do: "border-blue-200 bg-blue-50 text-blue-900 dark:border-blue-800 dark:bg-blue-950 dark:text-blue-100"
end
