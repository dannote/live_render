defmodule LiveRender.Components.Button do
  use LiveRender.Component,
    name: "button",
    description: "Clickable button. Use with on.press to trigger actions.",
    schema: [
      label: [type: :string, required: true, doc: "Button text"],
      variant: [
        type: {:in, [:default, :secondary, :destructive, :outline, :ghost]},
        default: :default,
        doc: "Visual style"
      ],
      disabled: [type: :boolean, default: false, doc: "Disabled state"]
    ]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <button class={["inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors h-9 px-4 py-2", variant_class(@variant)]} disabled={@disabled}>
      <%= @label %>
    </button>
    """
  end

  defp variant_class(:default), do: "bg-primary text-primary-foreground hover:bg-primary/90"

  defp variant_class(:secondary),
    do: "bg-secondary text-secondary-foreground hover:bg-secondary/80"

  defp variant_class(:destructive),
    do: "bg-destructive text-destructive-foreground hover:bg-destructive/90"

  defp variant_class(:outline),
    do: "border border-input bg-background hover:bg-accent hover:text-accent-foreground"

  defp variant_class(:ghost), do: "hover:bg-accent hover:text-accent-foreground"
end

defmodule LiveRender.Components.Tabs do
  use LiveRender.Component,
    name: "tabs",
    description:
      "Tabbed content container. Children must be tab_content elements with matching value props.",
    schema: [
      default_value: [type: :string, doc: "Initially active tab value"],
      tabs: [
        type: {:list, :map},
        required: true,
        doc: "Tab definitions with value and label"
      ]
    ],
    slots: [:inner_block]

  use Phoenix.Component

  def render(assigns) do
    tabs = assigns.tabs || []
    default = assigns.default_value || (List.first(tabs) || %{})["value"]
    tab_id = "tabs-#{System.unique_integer([:positive])}"
    assigns = assign(assigns, default: default, tab_id: tab_id, tabs: tabs)

    ~H"""
    <div id={@tab_id} phx-hook="LiveRenderTabs" data-active={@default}>
      <div class="inline-flex h-9 items-center justify-center rounded-lg bg-muted p-1 text-muted-foreground">
        <button
          :for={tab <- @tabs}
          data-tab-value={tab["value"]}
          phx-click={
            Phoenix.LiveView.JS.set_attribute({"data-active", tab["value"]}, to: "##{@tab_id}")
            |> Phoenix.LiveView.JS.dispatch("lr:tab-change", to: "##{@tab_id}")
          }
          class={[
            "inline-flex items-center justify-center whitespace-nowrap rounded-md px-3 py-1 text-sm font-medium ring-offset-background transition-all",
            "data-[state=active]:bg-background data-[state=active]:text-foreground data-[state=active]:shadow"
          ]}
        >
          <%= tab["label"] %>
        </button>
      </div>
      <div class="mt-3">
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end
end

defmodule LiveRender.Components.TabContent do
  use LiveRender.Component,
    name: "tab_content",
    description: "Content for a specific tab",
    schema: [
      value: [type: :string, required: true, doc: "Tab value this content belongs to"]
    ],
    slots: [:inner_block]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div data-tab-content={@value} class="hidden data-[state=active]:block">
      <%= render_slot(@inner_block) %>
    </div>
    """
  end
end
