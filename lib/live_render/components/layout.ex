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
    <div class={["flex", direction_class(@direction), gap_class(@gap)]}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  defp direction_class(:horizontal), do: "flex-row flex-wrap"
  defp direction_class(_), do: "flex-col"

  defp gap_class(0), do: "gap-0"
  defp gap_class(1), do: "gap-1"
  defp gap_class(2), do: "gap-2"
  defp gap_class(3), do: "gap-3"
  defp gap_class(4), do: "gap-4"
  defp gap_class(5), do: "gap-5"
  defp gap_class(6), do: "gap-6"
  defp gap_class(8), do: "gap-8"
  defp gap_class(_), do: "gap-3"
end

defmodule LiveRender.Components.Card do
  use LiveRender.Component,
    name: "card",
    description: "A card container with an optional title",
    schema: [
      title: [type: :string, doc: "Card title"],
      description: [type: :string, doc: "Card description"],
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
    <div class="rounded-xl border border-border bg-card text-card-foreground shadow-sm">
      <div :if={@title || @description} class="flex flex-col space-y-1.5 p-6 pb-0">
        <h3 :if={@title} class="text-lg font-semibold leading-none tracking-tight"><%= @title %></h3>
        <p :if={@description} class="text-sm text-muted-foreground"><%= @description %></p>
      </div>
      <div class="flex flex-col gap-3 p-6">
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end
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
    <div class={["grid", columns_class(@columns), gap_class(@gap)]}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  defp columns_class(1), do: "grid-cols-1"
  defp columns_class(2), do: "grid-cols-1 sm:grid-cols-2"
  defp columns_class(3), do: "grid-cols-1 sm:grid-cols-2 lg:grid-cols-3"
  defp columns_class(4), do: "grid-cols-1 sm:grid-cols-2 lg:grid-cols-4"
  defp columns_class(5), do: "grid-cols-1 sm:grid-cols-2 lg:grid-cols-5"
  defp columns_class(6), do: "grid-cols-1 sm:grid-cols-2 lg:grid-cols-6"
  defp columns_class(_), do: "grid-cols-1 sm:grid-cols-2"

  defp gap_class(0), do: "gap-0"
  defp gap_class(1), do: "gap-1"
  defp gap_class(2), do: "gap-2"
  defp gap_class(3), do: "gap-3"
  defp gap_class(4), do: "gap-4"
  defp gap_class(5), do: "gap-5"
  defp gap_class(6), do: "gap-6"
  defp gap_class(8), do: "gap-8"
  defp gap_class(_), do: "gap-3"
end

defmodule LiveRender.Components.Separator do
  use LiveRender.Component,
    name: "separator",
    description: "Horizontal separator line",
    schema: [
      orientation: [
        type: {:in, [:horizontal, :vertical]},
        default: :horizontal,
        doc: "Separator orientation"
      ]
    ]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <hr :if={@orientation == :horizontal} class="shrink-0 border-border my-3" />
    <div :if={@orientation == :vertical} class="shrink-0 bg-border w-px h-full mx-2" />
    """
  end
end
