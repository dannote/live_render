defmodule LiveRender.ComponentTest do
  use ExUnit.Case, async: true

  describe "component metadata" do
    test "exposes name and description" do
      assert LiveRender.Components.Metric.component_name() == "metric"
      assert LiveRender.Components.Metric.component_description() =~ "metric"
    end

    test "exposes slots" do
      assert LiveRender.Components.Card.component_slots() == [:inner_block]
      assert LiveRender.Components.Metric.component_slots() == []
    end

    test "generates JSON schema" do
      schema = LiveRender.Components.Metric.json_schema()
      assert schema["type"] == "object"
      assert schema["properties"]["label"]["type"] == "string"
      assert "label" in schema["required"]
      assert "value" in schema["required"]
    end

    test "validates props" do
      assert {:ok, %{label: "X", value: "42"}} =
               LiveRender.Components.Metric.validate_props(%{"label" => "X", "value" => "42"})
    end

    test "__component_meta__ returns full metadata" do
      meta = LiveRender.Components.Card.__component_meta__()
      assert meta.name == "card"
      assert meta.module == LiveRender.Components.Card
      assert meta.slots == [:inner_block]
    end
  end
end
