defmodule LiveRender.Component do
  @moduledoc """
  Defines a LiveRender component with schema-validated props and LLM metadata.

  ## Usage

  With NimbleOptions:

      defmodule MyApp.AI.Components.Metric do
        use LiveRender.Component,
          name: "metric",
          description: "Display a single metric value",
          schema: [
            label: [type: :string, required: true, doc: "Metric label"],
            value: [type: :string, required: true, doc: "Display value"],
            trend: [type: {:in, [:up, :down, :neutral]}, doc: "Trend direction"]
          ]

        use Phoenix.Component

        def render(assigns) do
          ~H"..."
        end
      end

  With JSONSpec:

      defmodule MyApp.AI.Components.Metric do
        import JSONSpec

        use LiveRender.Component,
          name: "metric",
          description: "Display a single metric value",
          schema: schema(
            %{
              required(:label) => String.t(),
              required(:value) => String.t(),
              optional(:trend) => :up | :down | :neutral
            },
            doc: [label: "Metric label", value: "Display value", trend: "Trend direction"]
          )

        use Phoenix.Component

        def render(assigns) do
          ~H"..."
        end
      end
  """

  @doc false
  defmacro __using__(opts) do
    quote do
      @moduledoc false

      @_lr_name Keyword.fetch!(unquote(opts), :name)
      @_lr_description Keyword.get(unquote(opts), :description, "")
      @_lr_schema Keyword.get(unquote(opts), :schema, [])
      @_lr_slots Keyword.get(unquote(opts), :slots, [])

      @doc "Component name used in specs."
      @spec component_name() :: String.t()
      def component_name, do: @_lr_name

      @doc "Component description for LLM prompts."
      @spec component_description() :: String.t()
      def component_description, do: @_lr_description

      @doc "Raw schema (NimbleOptions keyword list or JSONSpec map)."
      @spec component_schema() :: term()
      def component_schema, do: @_lr_schema

      @doc "Slot names this component accepts."
      @spec component_slots() :: [atom()]
      def component_slots, do: @_lr_slots

      @doc "Ordered list of prop keys for positional argument mapping."
      @spec prop_order() :: [atom()]
      def prop_order, do: LiveRender.Component.derive_prop_order(@_lr_schema, @_lr_slots)

      @doc "JSON Schema representation of the component props."
      @spec json_schema() :: map()
      def json_schema do
        LiveRender.SchemaAdapter.to_json_schema(@_lr_schema)
      end

      @doc "Validates props against the component schema."
      @spec validate_props(map()) :: {:ok, map()} | {:error, term()}
      def validate_props(props) do
        LiveRender.SchemaAdapter.validate(@_lr_schema, props)
      end

      @doc false
      def __component_meta__ do
        %{
          name: @_lr_name,
          module: __MODULE__,
          description: @_lr_description,
          schema: @_lr_schema,
          slots: @_lr_slots,
          prop_order: LiveRender.Component.derive_prop_order(@_lr_schema, @_lr_slots)
        }
      end
    end
  end

  @doc """
  Derives positional argument order from a component schema and slots.

  Components with an `:inner_block` slot get `:children` as the first positional arg.
  Remaining props follow schema key order.
  """
  @spec derive_prop_order(term(), [atom()]) :: [atom()]
  def derive_prop_order(schema, slots) do
    prefix = if :inner_block in slots, do: [:children], else: []
    prefix ++ schema_keys(schema)
  end

  defp schema_keys(schema) when is_list(schema), do: Keyword.keys(schema)
  defp schema_keys(schema) when is_map(schema), do: Map.keys(Map.get(schema, "properties", %{}))
  defp schema_keys(_), do: []
end
