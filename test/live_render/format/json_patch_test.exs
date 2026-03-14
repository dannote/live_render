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

  describe "edit mode (merge)" do
    test "prompt includes edit instructions when current_spec is provided" do
      current_spec = %{
        "root" => "main",
        "elements" => %{
          "main" => %{"type" => "heading", "props" => %{"text" => "Hi"}, "children" => []}
        }
      }

      prompt = JSONPatch.prompt(%{}, [], current_spec: current_spec)
      assert prompt =~ "__lr_edit"
      assert prompt =~ "Editing existing specs"
      assert prompt =~ "CURRENT UI STATE"
    end

    test "prompt omits edit instructions without current_spec" do
      prompt = JSONPatch.prompt(%{}, [], [])
      refute prompt =~ "__lr_edit"
      refute prompt =~ "Editing existing specs"
    end

    test "parse handles merge edit line in fence" do
      current_spec = %{
        "root" => "main",
        "elements" => %{
          "main" => %{"type" => "stack", "props" => %{}, "children" => ["heading"]},
          "heading" => %{"type" => "heading", "props" => %{"text" => "Old"}, "children" => []}
        }
      }

      text = """
      ```spec
      {"__lr_edit":true,"elements":{"heading":{"props":{"text":"New"}}}}
      ```
      """

      assert {:ok, spec} = JSONPatch.parse(text, current_spec: current_spec)
      assert spec["root"] == "main"
      assert spec["elements"]["heading"]["props"]["text"] == "New"
      assert spec["elements"]["heading"]["type"] == "heading"
      assert spec["elements"]["main"]["type"] == "stack"
    end

    test "streaming handles __lr_edit merge lines" do
      current_spec = %{
        "root" => "main",
        "elements" => %{
          "main" => %{"type" => "stack", "props" => %{}, "children" => ["heading"]},
          "heading" => %{"type" => "heading", "props" => %{"text" => "Old"}, "children" => []}
        }
      }

      state = JSONPatch.stream_init(current_spec: current_spec)
      {state, _} = JSONPatch.stream_push(state, "```spec\n")

      {_state, events} =
        JSONPatch.stream_push(
          state,
          ~s|{"__lr_edit":true,"elements":{"heading":{"props":{"text":"New"}}}}\n|
        )

      assert [{:spec, spec}] = events
      assert spec["root"] == "main"
      assert spec["elements"]["heading"]["props"]["text"] == "New"
      assert spec["elements"]["heading"]["type"] == "heading"
    end

    test "streaming supports mixing patches and merge edits" do
      current_spec = %{
        "root" => "main",
        "elements" => %{
          "main" => %{"type" => "stack", "props" => %{}, "children" => ["heading"]},
          "heading" => %{"type" => "heading", "props" => %{"text" => "Old"}, "children" => []}
        }
      }

      state = JSONPatch.stream_init(current_spec: current_spec)
      {state, _} = JSONPatch.stream_push(state, "```spec\n")

      # Merge edit
      {state, _} =
        JSONPatch.stream_push(
          state,
          ~s|{"__lr_edit":true,"elements":{"heading":{"props":{"text":"New"}}}}\n|
        )

      # Then a regular patch to add an element
      {_state, events} =
        JSONPatch.stream_push(
          state,
          ~s|{"op":"add","path":"/elements/metric","value":{"type":"metric","props":{"label":"Users"},"children":[]}}\n|
        )

      assert [{:spec, spec}] = events
      assert spec["elements"]["heading"]["props"]["text"] == "New"
      assert spec["elements"]["metric"]["type"] == "metric"
    end

    test "stream_init seeds spec from current_spec" do
      current_spec = %{
        "root" => "main",
        "elements" => %{
          "main" => %{"type" => "heading", "props" => %{}, "children" => []}
        }
      }

      state = JSONPatch.stream_init(current_spec: current_spec)
      assert state.spec["root"] == "main"
    end
  end
end
