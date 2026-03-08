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

  defp heading_class(:h1), do: "text-2xl font-bold text-left"
  defp heading_class(:h2), do: "text-lg font-semibold text-left"
  defp heading_class(:h3), do: "text-base font-semibold text-left"
  defp heading_class(:h4), do: "text-sm font-semibold text-left"
end

defmodule LiveRender.Components.Text do
  use LiveRender.Component,
    name: "text",
    description: "Text content",
    schema: [
      text: [type: :string, doc: "Text content"],
      content: [type: :string, doc: "Text content (alias for text)"],
      variant: [
        type: {:in, [:default, :muted, :caption, :lead, :code]},
        default: :default,
        doc: "Text variant"
      ]
    ]

  use Phoenix.Component

  def render(assigns) do
    text = assigns[:text] || assigns[:content] || ""
    assigns = assign(assigns, :display_text, text)

    ~H"""
    <code :if={@variant == :code} class="font-mono text-sm bg-muted px-1.5 py-0.5 rounded text-left">
      <%= @display_text %>
    </code>
    <p :if={@variant != :code} class={text_class(@variant)}>
      <%= @display_text %>
    </p>
    """
  end

  defp text_class(:caption), do: "text-xs text-left"
  defp text_class(:muted), do: "text-sm text-muted-foreground text-left"
  defp text_class(:lead), do: "text-xl text-muted-foreground text-left"
  defp text_class(_), do: "text-sm text-left"
end
