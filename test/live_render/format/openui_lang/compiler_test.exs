defmodule LiveRender.Format.OpenUILang.CompilerTest do
  use ExUnit.Case, async: true

  alias LiveRender.Format.OpenUILang.{Compiler, Parser}

  defp compile(input) do
    {:ok, assignments} = Parser.parse(input)
    Compiler.compile(assignments, LiveRender.StandardCatalog.components())
  end

  describe "compile/2" do
    test "compiles a heading" do
      spec = compile(~s|root = Heading("Hello World")|)

      assert spec["root"] == "root"
      assert spec["elements"]["root"]["type"] == "heading"
      assert spec["elements"]["root"]["props"]["text"] == "Hello World"
      assert spec["elements"]["root"]["children"] == []
    end

    test "compiles a metric with all positional args" do
      spec = compile(~s|root = Metric("Users", "1,234", "active", "up")|)

      assert spec["elements"]["root"]["type"] == "metric"
      assert spec["elements"]["root"]["props"]["label"] == "Users"
      assert spec["elements"]["root"]["props"]["value"] == "1,234"
      assert spec["elements"]["root"]["props"]["detail"] == "active"
      assert spec["elements"]["root"]["props"]["trend"] == "up"
    end

    test "compiles stack with children" do
      spec =
        compile("""
        root = Stack([h1, m1])
        h1 = Heading("Title")
        m1 = Metric("X", "42")
        """)

      assert spec["root"] == "root"
      assert spec["elements"]["root"]["type"] == "stack"
      assert spec["elements"]["root"]["children"] == ["h1", "m1"]
      assert spec["elements"]["h1"]["type"] == "heading"
      assert spec["elements"]["m1"]["type"] == "metric"
    end

    test "compiles card with children and props" do
      spec =
        compile("""
        root = Card([m1], "Weather", "Clear skies")
        m1 = Metric("Temp", "72°F")
        """)

      assert spec["elements"]["root"]["type"] == "card"
      assert spec["elements"]["root"]["props"]["title"] == "Weather"
      assert spec["elements"]["root"]["props"]["description"] == "Clear skies"
      assert spec["elements"]["root"]["children"] == ["m1"]
    end

    test "compiles grid with columns" do
      spec =
        compile("""
        root = Grid([a, b], 3)
        a = Heading("A")
        b = Heading("B")
        """)

      assert spec["elements"]["root"]["type"] == "grid"
      assert spec["elements"]["root"]["props"]["columns"] == 3
      assert spec["elements"]["root"]["children"] == ["a", "b"]
    end

    test "compiles badge" do
      spec = compile(~s|root = Badge("Active", "success")|)
      assert spec["elements"]["root"]["props"]["text"] == "Active"
      assert spec["elements"]["root"]["props"]["variant"] == "success"
    end

    test "compiles button with disabled" do
      spec = compile(~s|root = Button("Submit", "default", true)|)
      assert spec["elements"]["root"]["props"]["label"] == "Submit"
      assert spec["elements"]["root"]["props"]["disabled"] == true
    end

    test "first assignment becomes root" do
      spec =
        compile("""
        main = Stack([a])
        a = Heading("Hi")
        """)

      assert spec["root"] == "main"
    end

    test "compiles a complex dashboard" do
      spec =
        compile("""
        root = Stack([heading, grid1])
        heading = Heading("Weather Dashboard")
        grid1 = Grid([nyCard, londonCard], 2)
        nyCard = Card([nyTemp, nyWind], "New York")
        nyTemp = Metric("Temperature", "72°F")
        nyWind = Metric("Wind", "8 mph")
        londonCard = Card([londonTemp], "London")
        londonTemp = Metric("Temperature", "15°C")
        """)

      assert spec["root"] == "root"
      assert map_size(spec["elements"]) == 8
      assert spec["elements"]["root"]["children"] == ["heading", "grid1"]
      assert spec["elements"]["grid1"]["children"] == ["nyCard", "londonCard"]
      assert spec["elements"]["nyCard"]["children"] == ["nyTemp", "nyWind"]
      assert spec["elements"]["nyTemp"]["props"]["value"] == "72°F"
    end
  end

  describe "edge cases" do
    test "unknown component type produces empty element" do
      spec = compile(~s|root = FancyWidget("hello")|)

      assert spec["elements"]["root"]["type"] == "fancy_widget"
      assert spec["elements"]["root"]["props"] == %{}
      assert spec["elements"]["root"]["children"] == []
    end

    test "component with no args" do
      spec = compile(~s|root = Separator()|)

      assert spec["elements"]["root"]["type"] == "separator"
      assert spec["elements"]["root"]["props"] == %{}
    end

    test "non-component assignments are not elements" do
      spec =
        compile("""
        root = Heading("Hi")
        labels = ["Jan", "Feb"]
        """)

      assert map_size(spec["elements"]) == 1
      assert Map.has_key?(spec["elements"], "root")
      refute Map.has_key?(spec["elements"], "labels")
    end
  end

  describe "name conversion" do
    test "to_snake_case converts PascalCase" do
      assert Compiler.to_snake_case("Heading") == "heading"
      assert Compiler.to_snake_case("TabContent") == "tab_content"
      assert Compiler.to_snake_case("Stack") == "stack"
    end

    test "to_pascal_case converts snake_case" do
      assert Compiler.to_pascal_case("heading") == "Heading"
      assert Compiler.to_pascal_case("tab_content") == "TabContent"
      assert Compiler.to_pascal_case("stack") == "Stack"
    end
  end
end
