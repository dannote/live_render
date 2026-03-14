defmodule LiveRender.Format.JSONObjectTest do
  use ExUnit.Case, async: true

  alias LiveRender.Format.JSONObject

  describe "prompt/3" do
    test "generates a system prompt" do
      components = LiveRender.StandardCatalog.components()
      actions = LiveRender.StandardCatalog.actions()

      prompt = JSONObject.prompt(components, actions, [])
      assert prompt =~ "JSON object"
      assert prompt =~ "root"
      assert prompt =~ "elements"
      assert prompt =~ "metric"
    end
  end

  describe "parse/2" do
    test "parses JSON from a fenced block" do
      text = """
      ```spec
      {"root": "h1", "elements": {"h1": {"type": "heading", "props": {"text": "Hi"}, "children": []}}}
      ```
      """

      assert {:ok, spec} = JSONObject.parse(text)
      assert spec["root"] == "h1"
    end

    test "parses raw JSON" do
      text = ~s|{"root": "a", "elements": {"a": {"type": "text", "props": {}, "children": []}}}|
      assert {:ok, spec} = JSONObject.parse(text)
      assert spec["root"] == "a"
    end

    test "returns empty map for non-JSON" do
      assert {:ok, %{}} = JSONObject.parse("plain text")
    end

    test "returns empty map for JSON without root/elements" do
      assert {:ok, %{}} = JSONObject.parse(~s|{"foo": "bar"}|)
    end
  end

  describe "streaming" do
    test "accumulates JSON and emits spec" do
      state = JSONObject.stream_init()

      {state, events} = JSONObject.stream_push(state, "Here:\n```spec\n")
      assert [{:text, "Here:\n"}] = events

      {state, events} =
        JSONObject.stream_push(state, ~s|{"root": "a", "elements": {"a"|)

      assert events == []

      {_state, events} =
        JSONObject.stream_push(
          state,
          ~s|: {"type": "text", "props": {}, "children": []}}}\n```|
        )

      assert [{:spec, spec}] = events
      assert spec["root"] == "a"
    end

    test "stream_flush parses incomplete JSON with repair" do
      state = JSONObject.stream_init()
      {state, _} = JSONObject.stream_push(state, "```spec\n")

      {state, _} =
        JSONObject.stream_push(
          state,
          ~s|{"root": "a", "elements": {"a": {"type": "text", "props": {}, "children": []}|
        )

      {_state, events} = JSONObject.stream_flush(state)
      assert [{:spec, spec}] = events
      assert spec["root"] == "a"
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

      prompt = JSONObject.prompt(%{}, [], current_spec: current_spec)
      assert prompt =~ "Editing existing specs"
      assert prompt =~ "CURRENT UI STATE"
    end

    test "parse handles merge edit against current_spec" do
      current_spec = %{
        "root" => "main",
        "elements" => %{
          "main" => %{"type" => "stack", "props" => %{}, "children" => ["heading"]},
          "heading" => %{"type" => "heading", "props" => %{"text" => "Old"}, "children" => []}
        }
      }

      text = """
      ```spec
      {"elements":{"heading":{"props":{"text":"New"}}}}
      ```
      """

      assert {:ok, spec} = JSONObject.parse(text, current_spec: current_spec)
      assert spec["root"] == "main"
      assert spec["elements"]["heading"]["props"]["text"] == "New"
      assert spec["elements"]["heading"]["type"] == "heading"
    end

    test "streaming handles merge edit with current_spec" do
      current_spec = %{
        "root" => "main",
        "elements" => %{
          "main" => %{"type" => "stack", "props" => %{}, "children" => ["heading"]},
          "heading" => %{"type" => "heading", "props" => %{"text" => "Old"}, "children" => []}
        }
      }

      state = JSONObject.stream_init(current_spec: current_spec)
      {state, _} = JSONObject.stream_push(state, "```spec\n")

      {_state, events} =
        JSONObject.stream_push(
          state,
          ~s|{"elements":{"heading":{"props":{"text":"New"}}}}\n```|
        )

      assert [{:spec, spec}] = events
      assert spec["root"] == "main"
      assert spec["elements"]["heading"]["props"]["text"] == "New"
      assert spec["elements"]["heading"]["type"] == "heading"
    end

    test "stream_flush handles merge edit with current_spec" do
      current_spec = %{
        "root" => "main",
        "elements" => %{
          "main" => %{"type" => "heading", "props" => %{}, "children" => []}
        }
      }

      state = JSONObject.stream_init(current_spec: current_spec)
      {state, _} = JSONObject.stream_push(state, "```spec\n")

      {state, _} =
        JSONObject.stream_push(state, ~s|{"elements":{"main":{"props":{"text":"Updated"}}|)

      {_state, events} = JSONObject.stream_flush(state)
      assert [{:spec, spec}] = events
      assert spec["root"] == "main"
      assert spec["elements"]["main"]["props"]["text"] == "Updated"
      assert spec["elements"]["main"]["type"] == "heading"
    end
  end
end
