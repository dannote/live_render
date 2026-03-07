defmodule LiveRender.CatalogTest do
  use ExUnit.Case, async: true

  describe "StandardCatalog" do
    test "gets component by name" do
      assert LiveRender.StandardCatalog.get("card") == LiveRender.Components.Card
      assert LiveRender.StandardCatalog.get("metric") == LiveRender.Components.Metric
      assert LiveRender.StandardCatalog.get("nonexistent") == nil
    end

    test "lists all components" do
      components = LiveRender.StandardCatalog.components()
      assert is_map(components)
      assert Map.has_key?(components, "card")
      assert Map.has_key?(components, "stack")
      assert Map.has_key?(components, "metric")
      assert Map.has_key?(components, "button")
      assert Map.has_key?(components, "callout")
    end

    test "lists actions" do
      actions = LiveRender.StandardCatalog.actions()
      assert {:set_state, _desc} = List.keyfind(actions, :set_state, 0)
    end

    test "validates component props" do
      assert {:ok, %{label: "Temp", value: "72"}} =
               LiveRender.StandardCatalog.validate("metric", %{"label" => "Temp", "value" => "72"})
    end

    test "returns error for unknown component" do
      assert {:error, "unknown component: nope"} =
               LiveRender.StandardCatalog.validate("nope", %{})
    end

    test "generates system prompt" do
      prompt = LiveRender.StandardCatalog.system_prompt()
      assert is_binary(prompt)
      assert prompt =~ "card"
      assert prompt =~ "metric"
      assert prompt =~ "button"
      assert prompt =~ "set_state"
    end

    test "generates JSON schema" do
      schema = LiveRender.StandardCatalog.json_schema()
      assert schema["type"] == "object"
      assert schema["required"] == ["root", "elements"]

      assert is_list(
               schema["properties"]["elements"]["additionalProperties"]["properties"]["type"][
                 "enum"
               ]
             )
    end

    test "system_prompt accepts custom rules" do
      prompt =
        LiveRender.StandardCatalog.system_prompt(custom_rules: ["Always use Card for grouping"])

      assert prompt =~ "Always use Card for grouping"
    end
  end
end
