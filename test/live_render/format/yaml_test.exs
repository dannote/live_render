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

    test "parses YAML from a ```yaml fence" do
      text = """
      Here's a dashboard:

      ```yaml
      root: main
      elements:
        main:
          type: heading
          props:
            text: Hello
          children: []
      ```
      """

      assert {:ok, spec} = YAML.parse(text)
      assert spec["root"] == "main"
      assert spec["elements"]["main"]["props"]["text"] == "Hello"
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

      # root alone is not a valid spec — no emission yet
      {state, events} = YAML.stream_push(state, "root: main\n")
      assert events == []

      # elements with a type makes it valid — first emission
      {state, events} =
        YAML.stream_push(state, "elements:\n  main:\n    type: heading\n")

      assert [{:spec, spec}] = events
      assert spec["root"] == "main"
      assert spec["elements"]["main"]["type"] == "heading"

      {state, events} =
        YAML.stream_push(state, "    props:\n      text: Hello\n    children: []\n")

      assert [{:spec, spec}] = events
      assert spec["elements"]["main"]["props"]["text"] == "Hello"

      {_state, events} = YAML.stream_push(state, "```\n")
      assert events == []
    end

    test "detects ```yaml fence during streaming" do
      state = YAML.stream_init()

      {state, events} = YAML.stream_push(state, "Here:\n\n```yaml\n")
      assert [{:text, "Here:\n\n"}] = events

      {_state, events} =
        YAML.stream_push(
          state,
          "root: main\nelements:\n  main:\n    type: heading\n    props:\n      text: Hi\n    children: []\n"
        )

      assert [{:spec, spec}] = events
      assert spec["root"] == "main"
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

    test "stream_flush parses buffer that had no newline" do
      state = YAML.stream_init()
      {state, _} = YAML.stream_push(state, "```spec\n")

      # Single chunk with no newline — push skips parse
      {state, events} = YAML.stream_push(state, "root: x")
      assert events == []

      # Flush forces parse, but root-only is not valid (no elements)
      {_state, events} = YAML.stream_flush(state)
      assert events == []
    end

    test "waits for complete line before attempting parse" do
      state = YAML.stream_init()
      {state, _} = YAML.stream_push(state, "```spec\n")

      # Partial line, no newline — should not attempt parse
      {state, events} = YAML.stream_push(state, "root: ma")
      assert events == []

      # Complete the root line but still no elements — no spec emitted yet
      {state, events} = YAML.stream_push(state, "in\n")
      assert events == []

      # Add elements to make it a valid spec
      {_state, events} =
        YAML.stream_push(
          state,
          "elements:\n  main:\n    type: heading\n    props: {}\n    children: []\n"
        )

      assert [{:spec, spec}] = events
      assert spec["root"] == "main"
      assert spec["elements"]["main"]["type"] == "heading"
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

    test "does not emit spec with non-map elements" do
      state = YAML.stream_init()
      {state, _} = YAML.stream_push(state, "```spec\n")

      # "elements:" on same line as value would parse elements as a scalar
      {_state, events} = YAML.stream_push(state, "root: main\nelements: main\n")
      assert events == []
    end

    test "does not emit spec with string element values" do
      state = YAML.stream_init()
      {state, _} = YAML.stream_push(state, "```spec\n")

      # Intermediate parse: "main:\n    type" parses as %{"main" => "type"}
      {_state, events} = YAML.stream_push(state, "root: main\nelements:\n  main: type\n")
      assert events == []
    end

    test "does not emit spec without root" do
      state = YAML.stream_init()
      {state, _} = YAML.stream_push(state, "```spec\n")

      {_state, events} = YAML.stream_push(state, "elements:\n  main:\n    type: heading\n")
      assert events == []
    end

    test "emits no events when parse result unchanged" do
      state = YAML.stream_init()
      {state, _} = YAML.stream_push(state, "```spec\n")

      {state, _} =
        YAML.stream_push(
          state,
          "root: main\nelements:\n  main:\n    type: text\n    props: {}\n    children: []\n"
        )

      # Adding a blank line doesn't change the parsed result
      {_state, events} = YAML.stream_push(state, "\n")
      assert events == []
    end
  end
end
