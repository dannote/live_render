defmodule LiveRender.Format.SharedTest do
  use ExUnit.Case, async: true

  alias LiveRender.Format.Shared

  describe "components_section/1" do
    test "formats component docs" do
      components = LiveRender.StandardCatalog.components()
      section = Shared.components_section(components)

      assert section =~ "### card"
      assert section =~ "### metric"
      assert section =~ "(required)"
    end
  end

  describe "actions_section/1" do
    test "formats actions" do
      actions = LiveRender.StandardCatalog.actions()
      section = Shared.actions_section(actions)

      assert section =~ "set_state"
    end

    test "returns empty for no actions" do
      assert Shared.actions_section([]) == ""
    end
  end

  describe "rules_section/1" do
    test "formats custom rules" do
      section = Shared.rules_section(["Rule A", "Rule B"])
      assert section =~ "Rule A"
      assert section =~ "Rule B"
    end

    test "returns empty for no rules" do
      assert Shared.rules_section([]) == ""
    end
  end

  describe "detect_fence/2" do
    test "detects ```spec fence and splits before/after" do
      state = %{buffer: "", in_fence: false}
      {fields, events} = Shared.detect_fence(state, "Hello\n\n```spec\nroot = X()")

      assert fields.in_fence == true
      assert fields.buffer == "root = X()"
      assert [{:text, "Hello\n\n"}] = events
    end

    test "holds trailing backticks when no fence yet" do
      state = %{buffer: ""}
      {fields, events} = Shared.detect_fence(state, "some text``")

      assert fields.buffer == "``"
      assert [{:text, "some text"}] = events
    end

    test "passes through text with no backticks" do
      state = %{buffer: ""}
      {fields, events} = Shared.detect_fence(state, "plain text")

      assert fields.buffer == ""
      assert [{:text, "plain text"}] = events
    end
  end

  describe "hold_backticks/1" do
    test "holds trailing backticks" do
      assert {"text", "``"} = Shared.hold_backticks("text``")
      assert {"", "`"} = Shared.hold_backticks("`")
      assert {"abc", "```"} = Shared.hold_backticks("abc```")
    end

    test "passes through text without trailing backticks" do
      assert {"hello", ""} = Shared.hold_backticks("hello")
      assert {"", ""} = Shared.hold_backticks("")
    end
  end

  describe "split_lines/1" do
    test "splits complete lines from remainder" do
      {lines, remainder} = Shared.split_lines("a\nb\nc")
      assert lines == ["a", "b"]
      assert remainder == "c"
    end

    test "handles single line without newline" do
      {lines, remainder} = Shared.split_lines("hello")
      assert lines == []
      assert remainder == "hello"
    end

    test "handles trailing newline" do
      {lines, remainder} = Shared.split_lines("a\nb\n")
      assert lines == ["a", "b"]
      assert remainder == ""
    end
  end

  describe "json_prompt/4" do
    test "assembles full JSON prompt" do
      components = LiveRender.StandardCatalog.components()
      actions = LiveRender.StandardCatalog.actions()

      prompt = Shared.json_prompt("## Format\nSome format.", components, actions, [])

      assert prompt =~ "## Format"
      assert prompt =~ "Some format."
      assert prompt =~ "Data binding"
      assert prompt =~ "Visibility"
      assert prompt =~ "### card"
      assert prompt =~ "set_state"
    end
  end
end
