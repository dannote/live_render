defmodule LiveRender.Format.YAMLTest do
  use ExUnit.Case, async: true

  alias LiveRender.Format.YAML

  describe "prompt/3" do
    test "generates a YAML-specific system prompt" do
      components = LiveRender.StandardCatalog.components()
      actions = LiveRender.StandardCatalog.actions()

      prompt = YAML.prompt(components, actions, [])
      assert prompt =~ "YAML"
      assert prompt =~ "```spec"
      assert prompt =~ "root:"
      assert prompt =~ "elements:"
      assert prompt =~ "metric"
      assert prompt =~ "card"
    end

    test "includes custom rules" do
      prompt = YAML.prompt(%{}, [], custom_rules: ["Always use dark theme"])
      assert prompt =~ "Always use dark theme"
    end

    test "includes edit instructions when current_spec is provided" do
      current_spec = %{
        "root" => "main",
        "elements" => %{
          "main" => %{"type" => "heading", "props" => %{"text" => "Hi"}, "children" => []}
        }
      }

      prompt = YAML.prompt(%{}, [], current_spec: current_spec)
      assert prompt =~ "Editing existing specs"
      assert prompt =~ "deep merge"
      assert prompt =~ "CURRENT UI STATE"
      assert prompt =~ "main"
    end

    test "omits edit instructions when no current_spec" do
      prompt = YAML.prompt(%{}, [], [])
      refute prompt =~ "Editing existing specs"
      refute prompt =~ "CURRENT UI STATE"
    end
  end

  describe "parse/2" do
    test "parses YAML from a fenced block" do
      text = """
      Here's a dashboard:

      ```spec
      root: main
      elements:
        main:
          type: stack
          props: {}
          children:
            - heading
        heading:
          type: heading
          props:
            text: Hello
          children: []
      ```
      """

      assert {:ok, spec} = YAML.parse(text)
      assert spec["root"] == "main"
      assert spec["elements"]["heading"]["props"]["text"] == "Hello"
      assert spec["elements"]["main"]["children"] == ["heading"]
    end

    test "parses bare YAML without fence" do
      text = """
      root: a
      elements:
        a:
          type: text
          props:
            content: Hello
          children: []
      """

      assert {:ok, spec} = YAML.parse(text)
      assert spec["root"] == "a"
    end

    test "returns empty map for invalid YAML" do
      assert {:ok, %{}} = YAML.parse("not: valid: yaml: [")
    end

    test "returns empty map for JSON-like text" do
      assert {:ok, %{}} = YAML.parse(~s|{"foo": "bar"}|)
    end

    test "returns empty map for YAML without root/elements" do
      assert {:ok, %{}} = YAML.parse("foo: bar")
    end

    test "parses merge edit against current_spec" do
      current_spec = %{
        "root" => "main",
        "elements" => %{
          "main" => %{"type" => "stack", "props" => %{}, "children" => ["heading"]},
          "heading" => %{"type" => "heading", "props" => %{"text" => "Old"}, "children" => []}
        }
      }

      text = """
      ```spec
      elements:
        heading:
          props:
            text: New
      ```
      """

      assert {:ok, spec} = YAML.parse(text, current_spec: current_spec)
      assert spec["root"] == "main"
      assert spec["elements"]["heading"]["props"]["text"] == "New"
      assert spec["elements"]["heading"]["type"] == "heading"
      assert spec["elements"]["main"]["type"] == "stack"
    end

    test "merge edit with null deletes element" do
      current_spec = %{
        "root" => "main",
        "elements" => %{
          "main" => %{"type" => "stack", "props" => %{}, "children" => ["heading", "old"]},
          "heading" => %{"type" => "heading", "props" => %{"text" => "Hi"}, "children" => []},
          "old" => %{"type" => "text", "props" => %{}, "children" => []}
        }
      }

      text = """
      ```spec
      elements:
        old: null
        main:
          children:
            - heading
      ```
      """

      assert {:ok, spec} = YAML.parse(text, current_spec: current_spec)
      assert spec["root"] == "main"
      assert spec["elements"]["heading"]["type"] == "heading"
      refute Map.has_key?(spec["elements"], "old")
      assert spec["elements"]["main"]["children"] == ["heading"]
    end
  end

  describe "streaming" do
    test "progressively parses YAML and emits specs" do
      state = YAML.stream_init()

      {state, events} = YAML.stream_push(state, "Here's the UI:\n\n```spec\n")
      assert [{:text, "Here's the UI:\n\n"}] = events

      {state, events} = YAML.stream_push(state, "root: main\n")
      assert [{:spec, spec}] = events
      assert spec["root"] == "main"

      {state, events} =
        YAML.stream_push(state, "elements:\n  main:\n    type: heading\n")

      assert [{:spec, spec}] = events
      assert spec["elements"]["main"]["type"] == "heading"

      {state, events} =
        YAML.stream_push(state, "    props:\n      text: Hello\n    children: []\n")

      assert [{:spec, spec}] = events
      assert spec["elements"]["main"]["props"]["text"] == "Hello"

      {_state, events} = YAML.stream_push(state, "```\n")
      assert events == []
    end

    test "handles text before fence" do
      state = YAML.stream_init()
      {_state, events} = YAML.stream_push(state, "Let me build that.\n\n```spec\n")
      assert [{:text, "Let me build that.\n\n"}] = events
    end

    test "holds backticks to avoid partial fence detection" do
      state = YAML.stream_init()
      {state, events} = YAML.stream_push(state, "text`")
      assert [{:text, "text"}] = events

      {_state, events} = YAML.stream_push(state, "``spec\n")
      assert events == []
    end

    test "stream_flush processes remaining buffer without trailing newline" do
      state = YAML.stream_init()
      {state, _} = YAML.stream_push(state, "```spec\n")

      # No trailing newline — push won't attempt parse
      {state, events} = YAML.stream_push(state, "root: x")
      assert events == []

      {_state, events} = YAML.stream_flush(state)
      assert [{:spec, spec}] = events
      assert spec["root"] == "x"
    end

    test "waits for complete YAML before emitting" do
      state = YAML.stream_init()
      {state, _} = YAML.stream_push(state, "```spec\n")

      # Partial line, no newline — should not attempt parse
      {state, events} = YAML.stream_push(state, "root: ma")
      assert events == []

      # Complete the line
      {_state, events} = YAML.stream_push(state, "in\n")
      assert [{:spec, spec}] = events
      assert spec["root"] == "main"
    end

    test "streaming with merge edit against current_spec" do
      current_spec = %{
        "root" => "main",
        "elements" => %{
          "main" => %{"type" => "stack", "props" => %{}, "children" => ["heading"]},
          "heading" => %{"type" => "heading", "props" => %{"text" => "Old"}, "children" => []}
        }
      }

      state = YAML.stream_init(current_spec: current_spec)

      {state, _} = YAML.stream_push(state, "```spec\n")

      {_state, events} =
        YAML.stream_push(state, "elements:\n  heading:\n    props:\n      text: New\n")

      assert [{:spec, spec}] = events
      assert spec["root"] == "main"
      assert spec["elements"]["heading"]["props"]["text"] == "New"
      assert spec["elements"]["heading"]["type"] == "heading"
      assert spec["elements"]["main"]["type"] == "stack"
    end

    test "emits no events when parse result unchanged" do
      state = YAML.stream_init()
      {state, _} = YAML.stream_push(state, "```spec\n")
      {state, _} = YAML.stream_push(state, "root: main\n")

      # Same content, adding a comment-like blank line
      {_state, events} = YAML.stream_push(state, "\n")
      assert events == []
    end
  end
end
