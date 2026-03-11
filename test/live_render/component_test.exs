defmodule LiveRender.ComponentTest do
  use ExUnit.Case, async: true

  alias LiveRender.Components.Card
  alias LiveRender.Components.Metric

  describe "component metadata" do
    test "exposes name and description" do
      assert Metric.component_name() == "metric"
      assert Metric.component_description() =~ "metric"
    end

    test "exposes slots" do
      assert Card.component_slots() == [:inner_block]
      assert Metric.component_slots() == []
    end

    test "generates JSON schema" do
      schema = Metric.json_schema()
      assert schema["type"] == "object"
      assert schema["properties"]["label"]["type"] == "string"
      assert "label" in schema["required"]
      assert "value" in schema["required"]
    end

    test "validates props" do
      assert {:ok, %{label: "X", value: "42"}} =
               Metric.validate_props(%{"label" => "X", "value" => "42"})
    end

    test "__component_meta__ returns full metadata including prop_order" do
      meta = Card.__component_meta__()
      assert meta.name == "card"
      assert meta.module == Card
      assert meta.slots == [:inner_block]
      assert is_list(meta.prop_order)
      assert :children in meta.prop_order
    end

    test "prop_order puts children first for slotted components" do
      assert [:children | _] = Card.prop_order()
      assert [:children | _] = LiveRender.Components.Stack.prop_order()
    end

    test "prop_order has no children for non-slotted components" do
      order = Metric.prop_order()
      refute :children in order
      assert order == [:label, :value, :detail, :trend]
    end
  end

  describe "derive_prop_order/2" do
    test "keyword list schema preserves key order" do
      schema = [name: [type: :string], age: [type: :integer]]
      assert LiveRender.Component.derive_prop_order(schema, []) == [:name, :age]
    end

    test "prepends :children for inner_block slot" do
      schema = [title: [type: :string]]
      assert LiveRender.Component.derive_prop_order(schema, [:inner_block]) == [:children, :title]
    end

    test "no children prefix without inner_block slot" do
      schema = [label: [type: :string]]
      assert LiveRender.Component.derive_prop_order(schema, []) == [:label]
    end

    test "empty schema" do
      assert LiveRender.Component.derive_prop_order([], []) == []
      assert LiveRender.Component.derive_prop_order([], [:inner_block]) == [:children]
    end
  end
end
