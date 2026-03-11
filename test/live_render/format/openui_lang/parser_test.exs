defmodule LiveRender.Format.OpenUILang.ParserTest do
  use ExUnit.Case, async: true

  alias LiveRender.Format.OpenUILang.Parser

  describe "parse/1" do
    test "parses a single assignment with string" do
      assert {:ok, [{:assign, "title", {:string, "Hello"}}]} =
               Parser.parse(~s|title = "Hello"|)
    end

    test "parses a component call" do
      assert {:ok, [{:assign, "root", {:component, "Heading", [{:string, "Hello"}]}}]} =
               Parser.parse(~s|root = Heading("Hello")|)
    end

    test "parses multiple assignments" do
      input = """
      root = Stack([h1])
      h1 = Heading("Hello")
      """

      assert {:ok, assignments} = Parser.parse(input)
      assert length(assignments) == 2

      assert {:assign, "root", {:component, "Stack", [{:array, [{:ref, "h1"}]}]}} =
               Enum.at(assignments, 0)

      assert {:assign, "h1", {:component, "Heading", [{:string, "Hello"}]}} =
               Enum.at(assignments, 1)
    end

    test "parses component with multiple args" do
      input = ~s|m1 = Metric("Users", "1234", "active")|
      assert {:ok, [{:assign, "m1", {:component, "Metric", args}}]} = Parser.parse(input)
      assert length(args) == 3
    end

    test "parses nested arrays" do
      input = ~s|root = Stack([a, b, c])|

      assert {:ok, [{:assign, "root", {:component, "Stack", [{:array, refs}]}}]} =
               Parser.parse(input)

      assert length(refs) == 3
      assert Enum.all?(refs, &match?({:ref, _}, &1))
    end

    test "parses objects" do
      input = ~s|cfg = {variant: "info", size: 2}|
      assert {:ok, [{:assign, "cfg", {:object, pairs}}]} = Parser.parse(input)
      assert [{"variant", {:string, "info"}}, {"size", {:number, 2}}] = pairs
    end

    test "parses booleans and null" do
      assert {:ok, [{:assign, "a", {:boolean, true}}]} = Parser.parse("a = true")
      assert {:ok, [{:assign, "b", {:boolean, false}}]} = Parser.parse("b = false")
      assert {:ok, [{:assign, "c", :null}]} = Parser.parse("c = null")
    end

    test "parses numbers" do
      assert {:ok, [{:assign, "n", {:number, 42}}]} = Parser.parse("n = 42")
      assert {:ok, [{:assign, "f", {:number, 3.14}}]} = Parser.parse("f = 3.14")
    end

    test "handles forward references" do
      input = """
      root = Stack([chart])
      chart = BarChart(labels, [s1])
      labels = ["Jan", "Feb"]
      s1 = Series("A", [10, 20])
      """

      assert {:ok, assignments} = Parser.parse(input)
      assert length(assignments) == 4
    end

    test "handles empty input" do
      assert {:ok, []} = Parser.parse("")
      assert {:ok, []} = Parser.parse("\n\n\n")
    end

    test "handles comments" do
      input = """
      root = Heading("Hello") // this is a heading
      """

      assert {:ok, [{:assign, "root", {:component, "Heading", [{:string, "Hello"}]}}]} =
               Parser.parse(input)
    end

    test "errors on invalid syntax" do
      assert {:error, _} = Parser.parse("= no identifier")
    end
  end

  describe "parse_line/1" do
    test "parses a single line" do
      assert {:ok, {:assign, "root", {:component, "Heading", [{:string, "Hi"}]}}} =
               Parser.parse_line(~s|root = Heading("Hi")|)
    end

    test "returns nil for empty line" do
      assert {:ok, nil} = Parser.parse_line("")
    end
  end
end
