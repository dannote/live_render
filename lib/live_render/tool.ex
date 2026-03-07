if Code.ensure_loaded?(ReqLLM) do
  defmodule LiveRender.Tool do
    @moduledoc """
    Convenience for creating `ReqLLM.Tool` structs for use with `LiveRender.Generate`.

    Delegates to `ReqLLM.tool/1` — all schema formats supported by ReqLLM work here:
    NimbleOptions keyword lists, JSONSpec maps, or raw JSON Schema.

    ## Examples

        import JSONSpec

        # With JSONSpec (recommended — same syntax as json_spec)
        LiveRender.Tool.new(
          name: "get_weather",
          description: "Get current weather for a location",
          parameter_schema: schema(
            %{required(:location) => String.t(), optional(:units) => :celsius | :fahrenheit},
            doc: [location: "City name", units: "Temperature units"]
          ),
          callback: fn args ->
            location = args[:location] || args["location"]
            {:ok, %{temperature: 72, conditions: "sunny", location: location}}
          end
        )

        # With NimbleOptions
        LiveRender.Tool.new(
          name: "get_crypto_price",
          description: "Get current price for a cryptocurrency",
          parameter_schema: [
            symbol: [type: :string, required: true, doc: "Crypto symbol (BTC, ETH, etc.)"]
          ],
          callback: {MyApp.Crypto, :get_price}
        )

    ## Using in LiveRender.Generate

        tools = [
          LiveRender.Tool.new!(...),
          LiveRender.Tool.new!(...),
        ]

        LiveRender.Generate.stream_spec(model, prompt,
          catalog: MyApp.AI.Catalog,
          pid: self(),
          tools: tools
        )
    """

    @doc """
    Creates a new `ReqLLM.Tool` struct.

    Accepts the same options as `ReqLLM.Tool.new/1`:
    - `:name` — tool name (required)
    - `:description` — description for the LLM (required)
    - `:parameter_schema` — NimbleOptions, JSONSpec, or JSON Schema map
    - `:callback` — `fn/1`, `{Module, :function}`, or `{Module, :function, extra_args}`
    """
    @spec new(keyword()) :: {:ok, ReqLLM.Tool.t()} | {:error, term()}
    defdelegate new(opts), to: ReqLLM.Tool

    @doc "Same as `new/1` but raises on error."
    @spec new!(keyword()) :: ReqLLM.Tool.t()
    defdelegate new!(opts), to: ReqLLM.Tool
  end
end
