defmodule LiveRender.Format.JSONPatchTest do
  use ExUnit.Case, async: true

  alias LiveRender.Format.JSONPatch

  describe "prompt/3" do
    test "generates a system prompt with component docs" do
      components = LiveRender.StandardCatalog.components()
      actions = LiveRender.StandardCatalog.actions()

      prompt = JSONPatch.prompt(components, actions, [])
      assert prompt =~ "JSONL"
      assert prompt =~ "RFC 6902"
      assert prompt =~ "metric"
      assert prompt =~ "card"
      assert prompt =~ "set_state"
    end

    test "includes custom rules" do
      prompt =
        JSONPatch.prompt(%{}, [], custom_rules: ["Always use Card"])

      assert prompt =~ "Always use Card"
    end
  end

  describe "parse/2" do
    test "parses JSONL from a fenced block" do
      text = """
      Here's a dashboard:

      ```spec
      {"op":"add","path":"/root","value":"main"}
      {"op":"add","path":"/elements/main","value":{"type":"stack","props":{},"children":["h1"]}}
      {"op":"add","path":"/elements/h1","value":{"type":"heading","props":{"text":"Hello"},"children":[]}}
      ```
      """

      assert {:ok, spec} = JSONPatch.parse(text)
      assert spec["root"] == "main"
      assert spec["elements"]["h1"]["props"]["text"] == "Hello"
    end

    test "falls back to raw JSON" do
      text = ~s|{"root": "a", "elements": {"a": {"type": "text", "props": {}, "children": []}}}|
      assert {:ok, spec} = JSONPatch.parse(text)
      assert spec["root"] == "a"
    end

    test "returns empty map for plain text" do
      assert {:ok, %{}} = JSONPatch.parse("Just some text")
    end
  end

  describe "streaming" do
    test "accumulates patches progressively" do
      state = JSONPatch.stream_init()

      {state, events} = JSONPatch.stream_push(state, "Here's the UI:\n\n```spec\n")
      assert [{:text, "Here's the UI:\n\n"}] = events

      {state, events} =
        JSONPatch.stream_push(
          state,
          ~s|{"op":"add","path":"/root","value":"main"}\n|
        )

      assert [{:spec, spec}] = events
      assert spec["root"] == "main"

      {state, events} =
        JSONPatch.stream_push(
          state,
          ~s|{"op":"add","path":"/elements/main","value":{"type":"heading","props":{"text":"Hi"},"children":[]}}\n|
        )

      assert [{:spec, spec}] = events
      assert spec["elements"]["main"]["props"]["text"] == "Hi"

      {_state, events} = JSONPatch.stream_push(state, "```\n")
      assert events == []
    end

    test "handles text before fence" do
      state = JSONPatch.stream_init()
      {_state, events} = JSONPatch.stream_push(state, "Let me build that.\n\n```spec\n")
      assert [{:text, "Let me build that.\n\n"}] = events
    end

    test "holds backticks to avoid partial fence detection" do
      state = JSONPatch.stream_init()
      {state, events} = JSONPatch.stream_push(state, "text`")
      assert [{:text, "text"}] = events

      {_state, events} = JSONPatch.stream_push(state, "``spec\n")
      assert events == []
    end

    test "stream_flush processes remaining buffer" do
      state = JSONPatch.stream_init()

      {state, _} = JSONPatch.stream_push(state, "```spec\n")

      {state, _} =
        JSONPatch.stream_push(
          state,
          ~s|{"op":"add","path":"/root","value":"x"}|
        )

      {_state, events} = JSONPatch.stream_flush(state)
      assert [{:spec, spec}] = events
      assert spec["root"] == "x"
    end
  end
end
