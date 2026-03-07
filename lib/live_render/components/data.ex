defmodule LiveRender.Components.Metric do
  use LiveRender.Component,
    name: "metric",
    description: "Single metric display with label, value, and optional trend indicator",
    schema: [
      label: [type: :string, required: true, doc: "Metric label"],
      value: [type: :string, required: true, doc: "Display value"],
      detail: [type: :string, doc: "Additional detail text"],
      trend: [type: {:in, [:up, :down, :neutral]}, doc: "Trend direction"]
    ]

  use Phoenix.Component

  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:trend, fn -> nil end)
      |> assign_new(:detail, fn -> nil end)

    ~H"""
    <div class="flex flex-col gap-1">
      <span class="text-sm text-gray-500 dark:text-gray-400"><%= @label %></span>
      <div class="flex items-center gap-2">
        <span class="text-2xl font-bold"><%= @value %></span>
        <span :if={@trend} class={trend_class(@trend)}><%= trend_icon(@trend) %></span>
      </div>
      <span :if={@detail} class="text-xs text-gray-400"><%= @detail %></span>
    </div>
    """
  end

  defp trend_class(:up), do: "text-green-500"
  defp trend_class(:down), do: "text-red-500"
  defp trend_class(_), do: "text-gray-400"

  defp trend_icon(:up), do: "↑"
  defp trend_icon(:down), do: "↓"
  defp trend_icon(_), do: "–"
end

defmodule LiveRender.Components.Badge do
  use LiveRender.Component,
    name: "badge",
    description: "Small label badge for status or category",
    schema: [
      text: [type: :string, required: true, doc: "Badge text"],
      variant: [
        type: {:in, [:default, :success, :warning, :error, :info]},
        default: :default,
        doc: "Color variant"
      ]
    ]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <span class={["inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium", variant_class(@variant)]}>
      <%= @text %>
    </span>
    """
  end

  defp variant_class(:success),
    do: "bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400"

  defp variant_class(:warning),
    do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-400"

  defp variant_class(:error), do: "bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-400"

  defp variant_class(:info),
    do: "bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400"

  defp variant_class(_), do: "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300"
end

defmodule LiveRender.Components.Table do
  use LiveRender.Component,
    name: "table",
    description: "Data table with columns. Use {\"$state\": \"/path\"} to bind data.",
    schema: [
      data: [type: {:list, :map}, required: true, doc: "Array of row objects"],
      columns: [
        type:
          {:list,
           {:keyword_list,
            [key: [type: :string, required: true], label: [type: :string, required: true]]}},
        required: true,
        doc: "Column definitions with key and label"
      ],
      empty_message: [type: :string, default: "No data", doc: "Message shown when data is empty"]
    ]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div :if={@data == []} class="text-center py-4 text-gray-500"><%= @empty_message %></div>
    <table :if={@data != []} class="w-full text-sm">
      <thead>
        <tr class="border-b border-gray-200 dark:border-gray-700">
          <th :for={col <- @columns} class="text-left py-2 px-3 font-medium text-gray-500">
            <%= col[:label] %>
          </th>
        </tr>
      </thead>
      <tbody>
        <tr :for={row <- @data} class="border-b border-gray-100 dark:border-gray-800">
          <td :for={col <- @columns} class="py-2 px-3">
            <%= Map.get(row, col[:key], "") %>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end
end

defmodule LiveRender.Components.Link do
  use LiveRender.Component,
    name: "link",
    description: "External link that opens in a new tab",
    schema: [
      text: [type: :string, required: true, doc: "Link text"],
      href: [type: :string, required: true, doc: "URL"]
    ]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <a href={@href} target="_blank" rel="noopener noreferrer" class="text-blue-600 dark:text-blue-400 underline underline-offset-4 hover:opacity-80">
      <%= @text %>
    </a>
    """
  end
end
