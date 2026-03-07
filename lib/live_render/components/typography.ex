defmodule LiveRender.Components.Heading do
  use LiveRender.Component,
    name: "heading",
    description: "Section heading",
    schema: [
      text: [type: :string, required: true, doc: "Heading text"],
      level: [type: {:in, [:h1, :h2, :h3, :h4]}, default: :h2, doc: "Heading level"]
    ]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <.dynamic_tag tag_name={to_string(@level)} class={heading_class(@level)}>
      <%= @text %>
    </.dynamic_tag>
    """
  end

  defp heading_class(:h1), do: "text-2xl font-bold"
  defp heading_class(:h2), do: "text-xl font-semibold"
  defp heading_class(:h3), do: "text-lg font-semibold"
  defp heading_class(:h4), do: "text-base font-medium"
end

defmodule LiveRender.Components.Text do
  use LiveRender.Component,
    name: "text",
    description: "Text content",
    schema: [
      content: [type: :string, required: true, doc: "Text content"],
      muted: [type: :boolean, default: false, doc: "Use muted/secondary color"]
    ]

  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <p class={if @muted, do: "text-gray-500 dark:text-gray-400", else: ""}>
      <%= @content %>
    </p>
    """
  end
end
