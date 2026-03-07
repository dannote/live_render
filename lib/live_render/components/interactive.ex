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
    <button class={["px-4 py-2 rounded-lg text-sm font-medium transition-colors", variant_class(@variant)]} disabled={@disabled}>
      <%= @label %>
    </button>
    """
  end

  defp variant_class(:default), do: "bg-blue-600 text-white hover:bg-blue-700"

  defp variant_class(:secondary),
    do: "bg-gray-200 text-gray-800 hover:bg-gray-300 dark:bg-gray-700 dark:text-gray-200"

  defp variant_class(:destructive), do: "bg-red-600 text-white hover:bg-red-700"

  defp variant_class(:outline),
    do: "border border-gray-300 hover:bg-gray-50 dark:border-gray-600 dark:hover:bg-gray-800"

  defp variant_class(:ghost), do: "hover:bg-gray-100 dark:hover:bg-gray-800"
end

defmodule LiveRender.Components.Tabs do
  use LiveRender.Component,
    name: "tabs",
    description: "Tabbed content container",
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
    default = assigns.default_value || (List.first(assigns.tabs) || %{})["value"]
    assigns = assign(assigns, :default, default)

    ~H"""
    <div x-data={"{ activeTab: '#{@default}' }"}>
      <div class="flex border-b border-gray-200 dark:border-gray-700 mb-4">
        <button
          :for={tab <- @tabs}
          x-on:click={"activeTab = '#{tab["value"]}'"}
          x-bind:class={"activeTab === '#{tab["value"]}' ? 'border-blue-600 text-blue-600' : 'border-transparent text-gray-500 hover:text-gray-700'"}
          class="px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors"
        >
          <%= tab["label"] %>
        </button>
      </div>
      <%= render_slot(@inner_block) %>
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
    <div x-show={"activeTab === '#{@value}'"}>
      <%= render_slot(@inner_block) %>
    </div>
    """
  end
end
