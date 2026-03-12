defmodule LiveRender.Format.A2UITest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias LiveRender.Format.A2UI

  defp catalog_components do
    LiveRender.StandardCatalog.components()
  end

  defp parse_opts do
    [catalog: catalog_components()]
  end

  describe "prompt/3" do
    test "generates A2UI format prompt" do
      components = catalog_components()
      actions = LiveRender.StandardCatalog.actions()

      prompt = A2UI.prompt(components, actions, [])
      assert prompt =~ "A2UI"
      assert prompt =~ "createSurface"
      assert prompt =~ "updateComponents"
      assert prompt =~ "updateDataModel"
    end

    test "includes component signatures" do
      components = catalog_components()
      prompt = A2UI.prompt(components, [], [])
      assert prompt =~ "Heading"
      assert prompt =~ "Metric"
      assert prompt =~ "Stack"
    end

    test "includes custom rules" do
      components = catalog_components()
      prompt = A2UI.prompt(components, [], custom_rules: ["Use dark theme"])
      assert prompt =~ "Use dark theme"
    end
  end

  describe "parse/2" do
    test "parses A2UI JSONL from a fenced block" do
      text = """
      ```spec
      {"version":"v0.10","createSurface":{"surfaceId":"main","catalogId":"basic"}}
      {"version":"v0.10","updateComponents":{"surfaceId":"main","components":[{"id":"root","component":"Stack","children":["h1"]},{"id":"h1","component":"Text","text":"Hello"}]}}
      ```
      """

      assert {:ok, spec} = A2UI.parse(text, parse_opts())
      assert spec["root"] == "root"
      assert spec["elements"]["root"]["type"] == "stack"
      assert spec["elements"]["root"]["children"] == ["h1"]
      assert spec["elements"]["h1"]["type"] == "text"
      assert spec["elements"]["h1"]["props"]["text"] == "Hello"
    end

    test "parses data model updates" do
      text = """
      ```spec
      {"version":"v0.10","createSurface":{"surfaceId":"main","catalogId":"basic"}}
      {"version":"v0.10","updateComponents":{"surfaceId":"main","components":[{"id":"root","component":"Text","text":{"path":"/user/name"}}]}}
      {"version":"v0.10","updateDataModel":{"surfaceId":"main","path":"/user","value":{"name":"Alice"}}}
      ```
      """

      assert {:ok, spec} = A2UI.parse(text, parse_opts())
      assert spec["state"] == %{"user" => %{"name" => "Alice"}}
      assert spec["elements"]["root"]["props"]["text"] == %{"$state" => "/user/name"}
    end

    test "handles single child with child key" do
      text = """
      ```spec
      {"version":"v0.10","createSurface":{"surfaceId":"main","catalogId":"basic"}}
      {"version":"v0.10","updateComponents":{"surfaceId":"main","components":[{"id":"root","component":"Card","child":"content"},{"id":"content","component":"Text","text":"Inside card"}]}}
      ```
      """

      assert {:ok, spec} = A2UI.parse(text, parse_opts())
      assert spec["elements"]["root"]["children"] == ["content"]
    end

    test "converts data bindings to $state" do
      text = """
      ```spec
      {"version":"v0.10","updateComponents":{"surfaceId":"main","components":[{"id":"root","component":"Text","text":{"path":"/greeting"}}]}}
      ```
      """

      assert {:ok, spec} = A2UI.parse(text, parse_opts())
      assert spec["elements"]["root"]["props"]["text"] == %{"$state" => "/greeting"}
    end

    test "converts nested data bindings" do
      text = """
      ```spec
      {"version":"v0.10","updateComponents":{"surfaceId":"main","components":[{"id":"root","component":"Button","child":"label","action":{"event":{"name":"submit","context":{"userId":{"path":"/user/id"}}}}}]}}
      ```
      """

      assert {:ok, spec} = A2UI.parse(text, parse_opts())
      action = spec["elements"]["root"]["props"]["action"]
      assert action["event"]["context"]["userId"] == %{"$state" => "/user/id"}
    end

    test "deleteSurface clears the spec" do
      text = """
      ```spec
      {"version":"v0.10","createSurface":{"surfaceId":"main","catalogId":"basic"}}
      {"version":"v0.10","updateComponents":{"surfaceId":"main","components":[{"id":"root","component":"Text","text":"Hello"}]}}
      {"version":"v0.10","deleteSurface":{"surfaceId":"main"}}
      ```
      """

      assert {:ok, spec} = A2UI.parse(text, parse_opts())
      assert is_nil(spec["root"])
      assert spec["elements"] == %{}
    end

    test "returns empty map for plain text" do
      assert {:ok, %{}} = A2UI.parse("Just some text", parse_opts())
    end

    test "handles raw JSONL without fence" do
      text =
        ~s|{"version":"v0.10","updateComponents":{"surfaceId":"main","components":[{"id":"root","component":"Text","text":"Hi"}]}}|

      assert {:ok, spec} = A2UI.parse(text, parse_opts())
      assert spec["elements"]["root"]["props"]["text"] == "Hi"
    end

    test "replaces root data model with /" do
      text = """
      ```spec
      {"version":"v0.10","updateDataModel":{"surfaceId":"main","path":"/","value":{"counter":42}}}
      ```
      """

      assert {:ok, spec} = A2UI.parse(text, parse_opts())
      assert spec["state"] == %{"counter" => 42}
    end

    test "updates nested data model path" do
      text = """
      ```spec
      {"version":"v0.10","updateDataModel":{"surfaceId":"main","path":"/weather/temp","value":"72°F"}}
      ```
      """

      assert {:ok, spec} = A2UI.parse(text, parse_opts())
      assert spec["state"]["weather"]["temp"] == "72°F"
    end

    test "multiple updateDataModel calls accumulate" do
      text = """
      ```spec
      {"version":"v0.10","updateDataModel":{"surfaceId":"main","path":"/a","value":1}}
      {"version":"v0.10","updateDataModel":{"surfaceId":"main","path":"/b","value":2}}
      ```
      """

      assert {:ok, spec} = A2UI.parse(text, parse_opts())
      assert spec["state"]["a"] == 1
      assert spec["state"]["b"] == 2
    end

    test "strips reserved keys from props" do
      text = """
      ```spec
      {"version":"v0.10","updateComponents":{"surfaceId":"main","components":[{"id":"root","component":"Text","text":"Hi","accessibility":{"label":"greeting"}}]}}
      ```
      """

      assert {:ok, spec} = A2UI.parse(text, parse_opts())
      refute Map.has_key?(spec["elements"]["root"]["props"], "id")
      refute Map.has_key?(spec["elements"]["root"]["props"], "component")
      refute Map.has_key?(spec["elements"]["root"]["props"], "accessibility")
      assert spec["elements"]["root"]["props"]["text"] == "Hi"
    end
  end

  describe "end-to-end rendering" do
    test "parsed A2UI spec renders through LiveRender.render" do
      text = """
      ```spec
      {"version":"v0.10","createSurface":{"surfaceId":"main","catalogId":"basic"}}
      {"version":"v0.10","updateComponents":{"surfaceId":"main","components":[{"id":"root","component":"Stack","children":["heading","card1"]},{"id":"heading","component":"Heading","text":"Weather Dashboard"},{"id":"card1","component":"Card","child":"content"},{"id":"content","component":"Stack","children":["m1","m2"]},{"id":"m1","component":"Metric","label":"Temperature","value":"72°F"},{"id":"m2","component":"Metric","label":"Wind","value":"8 mph"}]}}
      ```
      """

      assert {:ok, spec} = A2UI.parse(text, parse_opts())

      assigns = %{spec: spec, catalog: LiveRender.StandardCatalog, streaming: false}

      html =
        rendered_to_string(~H"""
        <LiveRender.render spec={@spec} catalog={@catalog} streaming={@streaming} />
        """)

      assert html =~ "Weather Dashboard"
      assert html =~ "Temperature"
      assert html =~ "72°F"
      assert html =~ "Wind"
      assert html =~ "8 mph"
    end
  end

  describe "streaming" do
    test "emits text before fence and spec inside fence" do
      state = A2UI.stream_init(catalog: catalog_components())

      {state, events} = A2UI.stream_push(state, "Here it is:\n```spec\n")
      assert [{:text, "Here it is:\n"}] = events

      {_state, events} =
        A2UI.stream_push(
          state,
          ~s|{"version":"v0.10","updateComponents":{"surfaceId":"main","components":[{"id":"root","component":"Heading","text":"Hello"}]}}\n|
        )

      assert [{:spec, spec}] = events
      assert spec["root"] == "root"
      assert spec["elements"]["root"]["props"]["text"] == "Hello"
    end

    test "accumulates state across multiple messages" do
      state = A2UI.stream_init(catalog: catalog_components())
      {state, _} = A2UI.stream_push(state, "```spec\n")

      {state, events} =
        A2UI.stream_push(
          state,
          ~s|{"version":"v0.10","updateComponents":{"surfaceId":"main","components":[{"id":"root","component":"Text","text":{"path":"/name"}}]}}\n|
        )

      assert [{:spec, spec1}] = events
      assert spec1["elements"]["root"]["props"]["text"] == %{"$state" => "/name"}

      {_state, events} =
        A2UI.stream_push(
          state,
          ~s|{"version":"v0.10","updateDataModel":{"surfaceId":"main","path":"/name","value":"Alice"}}\n|
        )

      assert [{:spec, spec2}] = events
      assert spec2["state"]["name"] == "Alice"
      assert spec2["elements"]["root"]["props"]["text"] == %{"$state" => "/name"}
    end

    test "handles fence close" do
      state = A2UI.stream_init(catalog: catalog_components())
      {state, _} = A2UI.stream_push(state, "```spec\n")

      {state, _} =
        A2UI.stream_push(
          state,
          ~s|{"version":"v0.10","updateComponents":{"surfaceId":"main","components":[{"id":"root","component":"Text","text":"Hi"}]}}\n|
        )

      {state, _} = A2UI.stream_push(state, "```\n")
      refute state.in_fence
    end

    test "stream_flush processes remaining buffer" do
      state = A2UI.stream_init(catalog: catalog_components())
      {state, _} = A2UI.stream_push(state, "```spec\n")

      {state, _} =
        A2UI.stream_push(
          state,
          ~s|{"version":"v0.10","updateComponents":{"surfaceId":"main","components":[{"id":"root","component":"Heading","text":"Hi"}]}}|
        )

      {_state, events} = A2UI.stream_flush(state)
      assert [{:spec, spec}] = events
      assert spec["elements"]["root"]["type"] == "heading"
    end

    test "handles multiple lines in one chunk" do
      state = A2UI.stream_init(catalog: catalog_components())
      {state, _} = A2UI.stream_push(state, "```spec\n")

      chunk =
        [
          ~s|{"version":"v0.10","createSurface":{"surfaceId":"main","catalogId":"basic"}}|,
          ~s|{"version":"v0.10","updateComponents":{"surfaceId":"main","components":[{"id":"root","component":"Stack","children":["m1"]},{"id":"m1","component":"Metric","label":"X","value":"42"}]}}|,
          ""
        ]
        |> Enum.join("\n")

      {_state, events} = A2UI.stream_push(state, chunk)

      specs = for {:spec, s} <- events, do: s
      last_spec = List.last(specs)
      assert last_spec["elements"]["root"]["children"] == ["m1"]
      assert last_spec["elements"]["m1"]["props"]["label"] == "X"
    end

    test "stream_flush is no-op when not in fence" do
      state = A2UI.stream_init(catalog: catalog_components())
      {_state, events} = A2UI.stream_flush(state)
      assert events == []
    end

    test "stream_flush is no-op when buffer is empty" do
      state = A2UI.stream_init(catalog: catalog_components())
      {state, _} = A2UI.stream_push(state, "```spec\n")
      state = %{state | buffer: ""}
      {_state, events} = A2UI.stream_flush(state)
      assert events == []
    end

    test "progressive updateComponents merges elements" do
      state = A2UI.stream_init(catalog: catalog_components())
      {state, _} = A2UI.stream_push(state, "```spec\n")

      {state, _} =
        A2UI.stream_push(
          state,
          ~s|{"version":"v0.10","updateComponents":{"surfaceId":"main","components":[{"id":"root","component":"Stack","children":["h1","m1"]}]}}\n|
        )

      {_state, events} =
        A2UI.stream_push(
          state,
          ~s|{"version":"v0.10","updateComponents":{"surfaceId":"main","components":[{"id":"h1","component":"Heading","text":"Title"},{"id":"m1","component":"Metric","label":"X","value":"1"}]}}\n|
        )

      assert [{:spec, spec}] = events
      assert spec["elements"]["root"]["children"] == ["h1", "m1"]
      assert spec["elements"]["h1"]["props"]["text"] == "Title"
      assert spec["elements"]["m1"]["props"]["label"] == "X"
    end
  end
end
