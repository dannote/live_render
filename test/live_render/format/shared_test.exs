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
end
