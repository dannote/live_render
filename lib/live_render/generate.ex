if Code.ensure_loaded?(ReqLLM) do
  defmodule LiveRender.Generate do
    @moduledoc """
    LLM integration for generating UI specs using ReqLLM.

    Streams a UI spec from an LLM, sending incremental updates to a LiveView process.

    ## Usage in a LiveView

        def handle_event("generate", %{"prompt" => prompt}, socket) do
          LiveRender.Generate.stream_spec(
            "anthropic:claude-haiku-4-5",
            prompt,
            catalog: MyApp.AI.Catalog,
            pid: self()
          )

          {:noreply, assign(socket, spec: %{}, streaming?: true)}
        end

        def handle_info({:live_render, :text_chunk, text}, socket) do
          {:noreply, assign(socket, current_text: socket.assigns.current_text <> text)}
        end

        def handle_info({:live_render, :spec, spec}, socket) do
          {:noreply, assign(socket, spec: spec)}
        end

        def handle_info({:live_render, :tool_start, name}, socket) do
          # Show tool call status
        end

        def handle_info({:live_render, :tool_done, name, result}, socket) do
          # Tool call completed
        end

        def handle_info({:live_render, :done, response}, socket) do
          {:noreply, assign(socket, streaming?: false)}
        end

        def handle_info({:live_render, :error, reason}, socket) do
          {:noreply, put_flash(socket, :error, inspect(reason))}
        end

    ## With tools

        LiveRender.Generate.stream_spec(model, prompt,
          catalog: MyApp.AI.Catalog,
          pid: self(),
          tools: [
            ReqLLM.tool(
              name: "get_weather",
              description: "Get current weather for a location",
              parameter_schema: schema(%{required(:location) => String.t()}),
              callback: &MyApp.Weather.fetch/1
            )
          ]
        )
    """

    @spec_fence_regex ~r/```spec\n([\s\S]*?)(?:```|$)/

    @doc """
    Streams an LLM response that may contain text and a UI spec.

    The LLM is prompted with the catalog's system prompt and instructed to output
    a JSON spec wrapped in a `` ```spec `` fence when generating UI.

    ## Options

      * `:catalog` — catalog module (required)
      * `:pid` — process to receive messages (required)
      * `:tools` — list of `ReqLLM.Tool` structs or tool option keyword lists
      * `:model_opts` — extra options passed to `ReqLLM.stream_text/3` (temperature, max_tokens, etc.)
      * `:context` — prior conversation messages as `ReqLLM.Context` list
      * `:custom_rules` — additional rules for the system prompt
    """
    @spec stream_spec(String.t(), String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
    def stream_spec(model, prompt, opts) do
      catalog = Keyword.fetch!(opts, :catalog)
      pid = Keyword.fetch!(opts, :pid)
      tools = Keyword.get(opts, :tools, [])
      model_opts = Keyword.get(opts, :model_opts, [])
      context = Keyword.get(opts, :context, [])
      custom_rules = Keyword.get(opts, :custom_rules, [])

      system = build_system_prompt(catalog, custom_rules)
      messages = build_messages(system, context, prompt)

      req_opts =
        model_opts
        |> Keyword.put_new(:tools, build_tools(tools))

      Task.start(fn ->
        run_stream(model, messages, req_opts, pid)
      end)
    end

    @doc """
    Generates a complete UI spec (non-streaming).

    Returns the parsed spec map directly.

    ## Options

    Same as `stream_spec/3` except `:pid` is not needed.
    """
    @spec generate_spec(String.t(), String.t(), keyword()) ::
            {:ok, map()} | {:error, term()}
    def generate_spec(model, prompt, opts) do
      catalog = Keyword.fetch!(opts, :catalog)
      tools = Keyword.get(opts, :tools, [])
      model_opts = Keyword.get(opts, :model_opts, [])
      context = Keyword.get(opts, :context, [])
      custom_rules = Keyword.get(opts, :custom_rules, [])

      system = build_system_prompt(catalog, custom_rules)
      messages = build_messages(system, context, prompt)

      req_opts =
        model_opts
        |> Keyword.put_new(:tools, build_tools(tools))

      case ReqLLM.generate_text(model, messages, req_opts) do
        {:ok, response} ->
          text = ReqLLM.Response.text(response)
          {:ok, extract_spec(text)}

        {:error, _} = error ->
          error
      end
    end

    defp build_system_prompt(catalog, custom_rules) do
      base = catalog.system_prompt(custom_rules: custom_rules)

      base <>
        """


        ## Output format

        When generating UI, output a JSON spec wrapped in a ```spec fence:

        ```spec
        {"root": "...", "state": {...}, "elements": {...}}
        ```

        You may include text before and after the spec fence to explain what you built.
        Output root and elements so the UI streams progressively.
        Always call tools first to get real data before building the UI.
        """
    end

    defp build_messages(system, [], prompt) do
      [
        ReqLLM.Context.system(system),
        ReqLLM.Context.user(prompt)
      ]
    end

    defp build_messages(system, context, prompt) when is_list(context) do
      [ReqLLM.Context.system(system) | context ++ [ReqLLM.Context.user(prompt)]]
    end

    defp build_tools([]), do: []

    defp build_tools(tools) do
      Enum.map(tools, fn
        %ReqLLM.Tool{} = tool -> tool
        opts when is_list(opts) -> ReqLLM.Tool.new!(opts)
        %{} = tool_map -> tool_map
      end)
    end

    defp run_stream(model, messages, req_opts, pid) do
      case ReqLLM.stream_text(model, messages, req_opts) do
        {:ok, response} ->
          text_acc =
            response
            |> ReqLLM.StreamResponse.tokens()
            |> Enum.reduce("", fn token, acc ->
              send(pid, {:live_render, :text_chunk, token})
              acc <> token
            end)

          spec = extract_spec(text_acc)

          if spec != %{} do
            send(pid, {:live_render, :spec, spec})
          end

          send(pid, {:live_render, :done, response})

        {:error, reason} ->
          send(pid, {:live_render, :error, reason})
      end
    end

    defp extract_spec(text) do
      case Regex.run(@spec_fence_regex, text) do
        [_, json] -> parse_json(String.trim(json))
        nil -> try_parse_raw_json(text)
      end
    end

    defp try_parse_raw_json(text) do
      trimmed = String.trim(text)

      if String.starts_with?(trimmed, "{") do
        parse_json(trimmed)
      else
        %{}
      end
    end

    defp parse_json(str) do
      case Jason.decode(str) do
        {:ok, %{"root" => _, "elements" => _} = spec} -> spec
        _ -> %{}
      end
    end
  end
end
