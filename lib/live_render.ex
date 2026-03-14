defmodule LiveRender do
  @moduledoc """
  Server-driven generative UI for Phoenix LiveView.

  AI generates a JSON spec, LiveView resolves it to function components server-side,
  and LiveView diffs only the changed HTML over the WebSocket.

  ## Usage

      <LiveRender.render spec={@spec} catalog={MyApp.AI.Catalog} streaming={@streaming?} />

  The spec is a map with:
  - `"root"` — ID of the root element
  - `"state"` — state model for data binding (optional)
  - `"elements"` — map of element ID → element definition

  Each element has `"type"`, `"props"`, `"children"`, and optionally `"visible"` and `"on"`.
  """

  use Phoenix.Component

  alias LiveRender.StateResolver

  @doc """
  Renders a UI spec as a tree of Phoenix components.

  ## Attributes

    * `spec` — the JSON spec map
    * `catalog` — module that implements `LiveRender.Catalog`
    * `streaming` — whether the spec is still being streamed
    * `id` — unique ID prefix (auto-generated if omitted)
    * `class` — CSS class for the root wrapper
  """
  attr(:spec, :map, required: true)
  attr(:catalog, :atom, required: true)
  attr(:streaming, :boolean, default: false)
  attr(:id, :string)
  attr(:class, :any, default: nil)

  def render(assigns) do
    assigns = assign_new(assigns, :id, fn -> "lr-#{System.unique_integer([:positive])}" end)

    state = (assigns.spec && assigns.spec["state"]) || %{}
    root = assigns.spec && assigns.spec["root"]

    assigns =
      assigns
      |> assign(:state, state)
      |> assign(:root, root)

    ~H"""
    <div id={@id} data-live-render-id={@id} class={@class}>
      <.render_node
        :if={@root}
        spec={@spec}
        node_id={@root}
        catalog={@catalog}
        state={@state}
        streaming={@streaming}
        prefix={@id}
      />
    </div>
    """
  end

  attr(:spec, :map, required: true)
  attr(:node_id, :string, required: true)
  attr(:catalog, :atom, required: true)
  attr(:state, :map, required: true)
  attr(:streaming, :boolean, required: true)
  attr(:prefix, :string, required: true)

  defp render_node(assigns) do
    node = get_node(assigns.spec, assigns.node_id)
    component_mod = node && assigns.catalog.get(node["type"])

    if is_nil(component_mod) do
      ~H""
    else
      assigns = prepare_node_assigns(assigns, node, component_mod)

      ~H"""
      <div
        :if={@visible?}
        id={"#{@prefix}-#{@node_id}"}
        phx-update={if @freeze?, do: "ignore"}
        phx-hook={if @streaming, do: "LiveRenderEnter"}
      >
        <%= if @streaming do %>
          <% changed_keys = @component_assigns |> Map.keys() |> Enum.into(%{}, &{&1, true}) %>
          <%= @component_mod.render(Map.put(@component_assigns, :__changed__, changed_keys)) %>
        <% else %>
          <%= @component_mod.render(Map.put(@component_assigns, :__changed__, %{})) %>
        <% end %>
        <%= unless @has_children? and @has_slots? do %>
          <.render_node
            :for={child_id <- @children}
            spec={@spec}
            node_id={child_id}
            catalog={@catalog}
            state={@state}
            streaming={@streaming}
            prefix={@prefix}
          />
        <% end %>
      </div>
      """
    end
  end

  defp get_node(spec, node_id) do
    case spec["elements"] do
      elements when is_map(elements) ->
        case elements[node_id] do
          node when is_map(node) -> node
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp prepare_node_assigns(assigns, node, component_mod) do
    validated_props = resolve_and_validate(node, component_mod, assigns.state)
    children = if is_list(node["children"]), do: node["children"], else: []
    has_children? = children != []
    has_slots? = component_mod.component_slots() != []

    component_assigns =
      cond do
        has_children? and has_slots? ->
          Map.put(validated_props, :inner_block, build_inner_block(assigns, children))

        has_slots? ->
          Map.put(validated_props, :inner_block, [])

        true ->
          validated_props
      end

    assigns
    |> assign(:visible?, check_visibility(node["visible"], assigns.state))
    |> assign(:validated_props, validated_props)
    |> assign(:children, children)
    |> assign(:has_children?, has_children?)
    |> assign(:has_slots?, has_slots?)
    |> assign(:freeze?, not assigns.streaming)
    |> assign(:component_mod, component_mod)
    |> assign(:component_assigns, component_assigns)
  end

  defp resolve_and_validate(node, component_mod, state) do
    raw_props = if is_map(node["props"]), do: node["props"], else: %{}
    resolved = StateResolver.resolve(raw_props, state)

    case component_mod.validate_props(resolved) do
      {:ok, props} ->
        props

      {:error, _} ->
        atomize_keys(resolved)
        |> apply_schema_defaults(component_mod.component_schema())
        |> coerce_invalid_props(component_mod.component_schema())
    end
  end

  defp build_inner_block(assigns, children) do
    child_assigns = assign(assigns, :children, children)

    [
      %{
        __slot__: :inner_block,
        inner_block: fn _args, _caller ->
          render_children(child_assigns)
        end
      }
    ]
  end

  defp render_children(assigns) do
    ~H"""
    <.render_node
      :for={child_id <- @children}
      spec={@spec}
      node_id={child_id}
      catalog={@catalog}
      state={@state}
      streaming={@streaming}
      prefix={@prefix}
    />
    """
  end

  # --- Visibility ---

  defp check_visibility(nil, _state), do: true

  defp check_visibility(conditions, state) when is_list(conditions) do
    Enum.all?(conditions, &check_single_visibility(&1, state))
  end

  defp check_visibility(condition, state), do: check_single_visibility(condition, state)

  defp check_single_visibility(%{"$state" => path} = cond_map, state) do
    value = StateResolver.get_in_path(state, path)
    negate? = Map.get(cond_map, "not", false)

    result =
      case Map.get(cond_map, "eq") do
        nil -> !!value
        expected -> value == expected
      end

    if negate?, do: not result, else: result
  end

  defp check_single_visibility(val, _state), do: !!val

  # --- Helpers ---

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, val} when is_binary(key) -> {String.to_atom(key), val}
      {key, val} -> {key, val}
    end)
  end

  defp apply_schema_defaults(props, schema) when is_list(schema) do
    Enum.reduce(schema, props, fn {key, spec}, acc ->
      if Map.has_key?(acc, key), do: acc, else: Map.put(acc, key, spec[:default])
    end)
  end

  defp apply_schema_defaults(props, _schema), do: props

  defp coerce_invalid_props(props, schema) when is_list(schema) do
    Enum.reduce(schema, props, fn {key, spec}, acc ->
      coerce_prop(acc, key, spec)
    end)
  end

  defp coerce_invalid_props(props, _schema), do: props

  defp coerce_prop(props, key, spec) do
    val = Map.get(props, key)

    with {:in, allowed} <- spec[:type],
         false <- is_nil(val),
         false <- val in allowed do
      Map.put(props, key, spec[:default])
    else
      _ -> props
    end
  end
end
