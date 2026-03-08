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
      <span class="text-sm text-muted-foreground"><%= @label %></span>
      <div class="flex items-baseline gap-2">
        <span class="text-2xl font-bold"><%= display_value(@value) %></span>
        <span :if={@trend} class={trend_class(@trend)}><%= trend_icon(@trend) %></span>
      </div>
      <span :if={@detail} class="text-xs text-muted-foreground"><%= @detail %></span>
    </div>
    """
  end

  defp display_value(nil), do: "—"
  defp display_value(""), do: "—"
  defp display_value(v) when is_map(v), do: "—"
  defp display_value(v), do: v

  defp trend_class(:up), do: "text-green-500"
  defp trend_class(:down), do: "text-red-500"
  defp trend_class(_), do: "text-muted-foreground"

  defp trend_icon(:up), do: "↗"
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
    <span class={["inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-semibold transition-colors", variant_class(@variant)]}>
      <%= @text %>
    </span>
    """
  end

  defp variant_class(:success),
    do: "border-transparent bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400"

  defp variant_class(:warning),
    do: "border-transparent bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-400"

  defp variant_class(:error),
    do: "border-transparent bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-400"

  defp variant_class(:info),
    do: "border-transparent bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400"

  defp variant_class(_),
    do: "border-border bg-secondary text-secondary-foreground"
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
    assigns = update(assigns, :data, fn
      data when is_list(data) -> data
      _ -> []
    end)

    ~H"""
    <div :if={@data == []} class="text-center py-4 text-muted-foreground"><%= @empty_message %></div>
    <div :if={@data != []} class="rounded-md border border-border overflow-hidden">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-border bg-muted/50">
            <th :for={col <- @columns} class="text-left py-2.5 px-4 font-medium text-muted-foreground">
              <%= col_value(col, :label) %>
            </th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @data} class="border-b border-border last:border-0 transition-colors hover:bg-muted/50">
            <td :for={col <- @columns} class="py-2.5 px-4">
              <%= display_cell(row, col_value(col, :key)) %>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp col_value(col, key) when is_map(col), do: col[to_string(key)] || col[key]
  defp col_value(col, key) when is_list(col), do: Keyword.get(col, key)
  defp col_value(_, _), do: nil

  defp display_cell(row, key) when is_binary(key), do: to_string(Map.get(row, key, ""))
  defp display_cell(_, _), do: ""
end

defmodule LiveRender.Components.Link do
  use LiveRender.Component,
    name: "link",
    description: "External link that opens in a new tab",
    schema: [
      text: [type: :string, required: true, doc: "Link text"],
      href: [type: :string, required: true, doc: "URL"],
      label: [type: :string, doc: "Link text (alias for text)"]
    ]

  use Phoenix.Component

  def render(assigns) do
    text = assigns[:text] || assigns[:label] || ""
    assigns = assign(assigns, :display_text, text)

    ~H"""
    <a href={@href} target="_blank" rel="noopener noreferrer" class="text-primary underline-offset-4 hover:underline text-sm font-medium">
      <%= @display_text %>
    </a>
    """
  end
end
