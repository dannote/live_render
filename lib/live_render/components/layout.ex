defmodule LiveRender.Components.Stack do
  use LiveRender.Component,
    name: "stack",
    description: "Layout container that stacks children vertically or horizontally",
    schema: [
      direction: [
        type: {:in, [:vertical, :horizontal]},
        default: :vertical,
        doc: "Stack direction"
      ],
      gap: [type: :integer, default: 4, doc: "Gap between children (Tailwind spacing scale)"]
    ],
    slots: [:inner_block]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div class={["flex", direction_class(@direction), "gap-#{@gap}"]}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  defp direction_class(:horizontal), do: "flex-row"
  defp direction_class(_), do: "flex-col"
end

defmodule LiveRender.Components.Card do
  use LiveRender.Component,
    name: "card",
    description: "A card container with an optional title",
    schema: [
      title: [type: :string, doc: "Card title"],
      variant: [
        type: {:in, [:default, :bordered, :shadow]},
        default: :default,
        doc: "Visual style"
      ]
    ],
    slots: [:inner_block]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div class={["rounded-lg p-4", variant_class(@variant)]}>
      <h3 :if={@title} class="text-lg font-semibold mb-3"><%= @title %></h3>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  defp variant_class(:bordered), do: "border border-gray-200 dark:border-gray-700"
  defp variant_class(:shadow), do: "bg-white dark:bg-gray-800 shadow-md"
  defp variant_class(_), do: "bg-gray-50 dark:bg-gray-800/50"
end

defmodule LiveRender.Components.Grid do
  use LiveRender.Component,
    name: "grid",
    description: "CSS grid layout with configurable columns",
    schema: [
      columns: [type: :integer, default: 2, doc: "Number of columns"],
      gap: [type: :integer, default: 4, doc: "Gap between items"]
    ],
    slots: [:inner_block]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div class={["grid", columns_class(@columns), "gap-#{@gap}"]}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  defp columns_class(1), do: "grid-cols-1"
  defp columns_class(2), do: "grid-cols-1 md:grid-cols-2"
  defp columns_class(3), do: "grid-cols-1 md:grid-cols-2 lg:grid-cols-3"
  defp columns_class(4), do: "grid-cols-1 md:grid-cols-2 lg:grid-cols-4"
  defp columns_class(_), do: "grid-cols-1 md:grid-cols-2"
end

defmodule LiveRender.Components.Separator do
  use LiveRender.Component,
    name: "separator",
    description: "Horizontal separator line",
    schema: []

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <hr class="border-gray-200 dark:border-gray-700" />
    """
  end
end
