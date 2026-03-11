defmodule LiveRender.Format.OpenUILangTest do
  use ExUnit.Case, async: true

  alias LiveRender.Format.OpenUILang

  defp catalog_components do
    LiveRender.StandardCatalog.components()
  end

  defp parse_opts do
    [catalog: catalog_components()]
  end

  describe "prompt/3" do
    test "generates signatures with positional args" do
      components = catalog_components()
      prompt = OpenUILang.prompt(components, [], [])

      assert prompt =~ "OpenUI Lang"
      assert prompt =~ "Heading("
      assert prompt =~ "Metric("
      assert prompt =~ "Stack("
    end

    test "includes component descriptions" do
      components = catalog_components()
      prompt = OpenUILang.prompt(components, [], [])
      assert prompt =~ "metric"
    end

    test "marks optional args" do
      components = catalog_components()
      prompt = OpenUILang.prompt(components, [], [])
      assert prompt =~ "?"
    end
  end

  describe "parse/2" do
    test "parses a simple component" do
      text = """
      ```spec
      root = Heading("Hello World")
      ```
      """

      assert {:ok, spec} = OpenUILang.parse(text, parse_opts())
      assert spec["root"] == "root"
      assert spec["elements"]["root"]["type"] == "heading"
      assert spec["elements"]["root"]["props"]["text"] == "Hello World"
    end

    test "parses nested components with children" do
      text = """
      ```spec
      root = Stack([heading, metric1])
      heading = Heading("Dashboard")
      metric1 = Metric("Users", "1,234")
      ```
      """

      assert {:ok, spec} = OpenUILang.parse(text, parse_opts())
      assert spec["root"] == "root"
      assert spec["elements"]["root"]["type"] == "stack"
      assert spec["elements"]["root"]["children"] == ["heading", "metric1"]
      assert spec["elements"]["heading"]["props"]["text"] == "Dashboard"
      assert spec["elements"]["metric1"]["props"]["label"] == "Users"
      assert spec["elements"]["metric1"]["props"]["value"] == "1,234"
    end

    test "parses card with title and children" do
      text = """
      ```spec
      root = Card([m1], "Weather")
      m1 = Metric("Temperature", "72°F")
      ```
      """

      assert {:ok, spec} = OpenUILang.parse(text, parse_opts())
      assert spec["elements"]["root"]["type"] == "card"
      assert spec["elements"]["root"]["props"]["title"] == "Weather"
      assert spec["elements"]["root"]["children"] == ["m1"]
    end

    test "parses grid with column count" do
      text = """
      ```spec
      root = Grid([card1, card2], 3)
      card1 = Card([m1], "A")
      card2 = Card([m2], "B")
      m1 = Metric("X", "1")
      m2 = Metric("Y", "2")
      ```
      """

      assert {:ok, spec} = OpenUILang.parse(text, parse_opts())
      assert spec["elements"]["root"]["type"] == "grid"
      assert spec["elements"]["root"]["props"]["columns"] == 3
      assert spec["elements"]["root"]["children"] == ["card1", "card2"]
    end

    test "parses badge with variant" do
      text = """
      ```spec
      root = Badge("Active", "success")
      ```
      """

      assert {:ok, spec} = OpenUILang.parse(text, parse_opts())
      assert spec["elements"]["root"]["props"]["text"] == "Active"
      assert spec["elements"]["root"]["props"]["variant"] == "success"
    end

    test "parses boolean and null values" do
      text = """
      ```spec
      root = Button("Submit", "default", true)
      ```
      """

      assert {:ok, spec} = OpenUILang.parse(text, parse_opts())
      assert spec["elements"]["root"]["props"]["label"] == "Submit"
      assert spec["elements"]["root"]["props"]["disabled"] == true
    end

    test "parses object values" do
      text = """
      ```spec
      root = Metric("Temp", "72°F")
      ```
      """

      assert {:ok, spec} = OpenUILang.parse(text, parse_opts())
      assert spec["elements"]["root"]["props"]["value"] == "72°F"
    end

    test "returns empty map for plain text" do
      assert {:ok, %{}} = OpenUILang.parse("Just some text", parse_opts())
    end

    test "returns empty map for invalid syntax" do
      text = """
      ```spec
      this is not valid
      ```
      """

      assert {:ok, %{}} = OpenUILang.parse(text, parse_opts())
    end

    test "handles raw OpenUI Lang without fence" do
      text = """
      root = Heading("Hello")
      """

      assert {:ok, spec} = OpenUILang.parse(text, parse_opts())
      assert spec["root"] == "root"
      assert spec["elements"]["root"]["type"] == "heading"
    end
  end

  describe "streaming" do
    test "builds spec progressively line by line" do
      state = OpenUILang.stream_init(catalog: catalog_components())

      {state, events} = OpenUILang.stream_push(state, "Here it is:\n```spec\n")
      assert [{:text, "Here it is:\n"}] = events

      {state, events} = OpenUILang.stream_push(state, "root = Stack([h1])\n")
      assert [{:spec, spec}] = events
      assert spec["root"] == "root"
      assert spec["elements"]["root"]["children"] == ["h1"]

      {_state, events} = OpenUILang.stream_push(state, "h1 = Heading(\"Hello\")\n")
      assert [{:spec, spec}] = events
      assert spec["elements"]["h1"]["props"]["text"] == "Hello"
    end

    test "handles fence close" do
      state = OpenUILang.stream_init(catalog: catalog_components())
      {state, _} = OpenUILang.stream_push(state, "```spec\n")
      {state, _} = OpenUILang.stream_push(state, "root = Heading(\"Hi\")\n")
      {state, _events} = OpenUILang.stream_push(state, "```\n")
      refute state.in_fence
    end

    test "stream_flush processes remaining buffer" do
      state = OpenUILang.stream_init(catalog: catalog_components())
      {state, _} = OpenUILang.stream_push(state, "```spec\n")
      {state, _} = OpenUILang.stream_push(state, "root = Heading(\"Hi\")")

      {_state, events} = OpenUILang.stream_flush(state)
      assert [{:spec, spec}] = events
      assert spec["elements"]["root"]["type"] == "heading"
    end
  end
end
