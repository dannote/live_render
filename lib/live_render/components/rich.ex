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
        <span class="text-lg"><%= callout_icon(@type) %></span>
        <div>
          <p :if={@title} class="font-semibold text-sm mb-1"><%= @title %></p>
          <p class="text-sm text-gray-600 dark:text-gray-400"><%= @content %></p>
        </div>
      </div>
    </div>
    """
  end

  defp callout_class(:info), do: "border-blue-500 bg-blue-50 dark:bg-blue-900/10"
  defp callout_class(:tip), do: "border-emerald-500 bg-emerald-50 dark:bg-emerald-900/10"
  defp callout_class(:warning), do: "border-amber-500 bg-amber-50 dark:bg-amber-900/10"
  defp callout_class(:important), do: "border-purple-500 bg-purple-50 dark:bg-purple-900/10"

  defp callout_icon(:info), do: "ℹ"
  defp callout_icon(:tip), do: "💡"
  defp callout_icon(:warning), do: "⚠"
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
      <div class="absolute left-[5.5px] top-3 bottom-3 w-px bg-gray-200 dark:bg-gray-700" />
      <div class="flex flex-col gap-6">
        <div :for={item <- @items} class="relative">
          <div class={["absolute -left-8 top-0.5 h-3 w-3 rounded-full ring-2 ring-white dark:ring-gray-900", dot_class(item["status"])]}>
          </div>
          <div>
            <div class="flex items-center gap-2 flex-wrap">
              <p class="font-medium text-sm"><%= item["title"] %></p>
              <span :if={item["date"]} class="text-xs text-gray-500 bg-gray-100 dark:bg-gray-800 px-1.5 py-0.5 rounded">
                <%= item["date"] %>
              </span>
            </div>
            <p :if={item["description"]} class="text-sm text-gray-500 mt-1">
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
  defp dot_class("upcoming"), do: "bg-gray-300 dark:bg-gray-600"
  defp dot_class(_), do: "bg-gray-400"
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
    <div class="divide-y divide-gray-200 dark:divide-gray-700 border border-gray-200 dark:border-gray-700 rounded-lg">
      <details :for={item <- @items} class="group">
        <summary class="flex items-center justify-between px-4 py-3 cursor-pointer text-sm font-medium hover:bg-gray-50 dark:hover:bg-gray-800/50">
          <%= item["title"] %>
          <span class="text-gray-400 group-open:rotate-180 transition-transform">▾</span>
        </summary>
        <div class="px-4 pb-3 text-sm text-gray-600 dark:text-gray-400">
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
      label: [type: :string, doc: "Label text"],
      color: [
        type: {:in, [:default, :success, :warning, :error]},
        default: :default,
        doc: "Bar color"
      ]
    ]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div>
      <div :if={@label} class="flex justify-between text-sm mb-1">
        <span><%= @label %></span>
        <span class="text-gray-500"><%= @value %>%</span>
      </div>
      <div class="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2">
        <div class={["h-2 rounded-full transition-all", bar_color(@color)]} style={"width: #{min(max(@value, 0), 100)}%"}>
        </div>
      </div>
    </div>
    """
  end

  defp bar_color(:success), do: "bg-emerald-500"
  defp bar_color(:warning), do: "bg-amber-500"
  defp bar_color(:error), do: "bg-red-500"
  defp bar_color(_), do: "bg-blue-600"
end

defmodule LiveRender.Components.Alert do
  use LiveRender.Component,
    name: "alert",
    description: "Alert message",
    schema: [
      message: [type: :string, required: true, doc: "Alert message"],
      variant: [
        type: {:in, [:info, :success, :warning, :error]},
        default: :info,
        doc: "Alert type"
      ]
    ]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div class={["px-4 py-3 rounded-lg text-sm", alert_class(@variant)]}>
      <%= @message %>
    </div>
    """
  end

  defp alert_class(:success),
    do: "bg-emerald-50 text-emerald-800 dark:bg-emerald-900/20 dark:text-emerald-400"

  defp alert_class(:warning),
    do: "bg-amber-50 text-amber-800 dark:bg-amber-900/20 dark:text-amber-400"

  defp alert_class(:error), do: "bg-red-50 text-red-800 dark:bg-red-900/20 dark:text-red-400"
  defp alert_class(_), do: "bg-blue-50 text-blue-800 dark:bg-blue-900/20 dark:text-blue-400"
end
