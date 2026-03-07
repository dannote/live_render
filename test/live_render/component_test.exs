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

    test "__component_meta__ returns full metadata" do
      meta = Card.__component_meta__()
      assert meta.name == "card"
      assert meta.module == Card
      assert meta.slots == [:inner_block]
    end
  end
end
