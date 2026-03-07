defmodule LiveRender.Catalog do
  @moduledoc """
  Collects LiveRender components and actions into a catalog that generates
  LLM system prompts and resolves component types at render time.

  ## Usage

      defmodule MyApp.AI.Catalog do
        use LiveRender.Catalog

        component MyApp.AI.Components.Card
        component MyApp.AI.Components.Metric
        component MyApp.AI.Components.Button

        action :refresh_data, description: "Refresh all metrics"
      end

  Then in your LiveView:

      <LiveRender.render spec={@spec} catalog={MyApp.AI.Catalog} />

  Or generate a prompt for the LLM:

      MyApp.AI.Catalog.system_prompt()
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import LiveRender.Catalog, only: [component: 1, action: 2]
      Module.register_attribute(__MODULE__, :_lr_components, accumulate: true)
      Module.register_attribute(__MODULE__, :_lr_actions, accumulate: true)

      @before_compile LiveRender.Catalog
    end
  end

  @doc "Registers a component module in the catalog."
  defmacro component(module) do
    quote do
      @_lr_components unquote(module)
    end
  end

  @doc "Registers an action the LLM can reference."
  defmacro action(name, opts) do
    quote do
      @_lr_actions {unquote(name), unquote(opts)}
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    components = Module.get_attribute(env.module, :_lr_components) |> Enum.reverse()
    actions = Module.get_attribute(env.module, :_lr_actions) |> Enum.reverse()

    component_map =
      for mod <- components, into: %{} do
        # Access the module's __component_meta__ at compile time
        {mod.__component_meta__().name, mod}
      end

    action_list =
      for {name, opts} <- actions do
        {name, Keyword.get(opts, :description, "")}
      end

    quote do
      @_component_map unquote(Macro.escape(component_map))
      @_action_list unquote(Macro.escape(action_list))

      @doc "Looks up a component module by its spec type name."
      @spec get(String.t()) :: module() | nil
      def get(name), do: Map.get(@_component_map, name)

      @doc "Validates props for a component type."
      @spec validate(String.t(), map()) :: {:ok, map()} | {:error, term()}
      def validate(name, props) do
        case get(name) do
          nil -> {:error, "unknown component: #{name}"}
          mod -> mod.validate_props(props)
        end
      end

      @doc "All registered component modules."
      @spec components() :: %{String.t() => module()}
      def components, do: @_component_map

      @doc "All registered actions."
      @spec actions() :: [{atom(), String.t()}]
      def actions, do: @_action_list

      @doc "Generates a system prompt describing all components and actions for the LLM."
      @spec system_prompt(keyword()) :: String.t()
      def system_prompt(opts \\ []) do
        LiveRender.Catalog.Builder.build(@_component_map, @_action_list, opts)
      end

      @doc "Full JSON Schema for the spec format (for structured output mode)."
      @spec json_schema() :: map()
      def json_schema do
        LiveRender.Catalog.Builder.spec_json_schema(@_component_map)
      end
    end
  end
end
