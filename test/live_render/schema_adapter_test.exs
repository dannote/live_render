defmodule LiveRender.SchemaAdapterTest do
  use ExUnit.Case, async: true

  alias LiveRender.SchemaAdapter

  describe "to_json_schema/1 with NimbleOptions" do
    test "converts basic types" do
      schema = [
        name: [type: :string, required: true, doc: "User name"],
        age: [type: :integer],
        active: [type: :boolean]
      ]

      result = SchemaAdapter.to_json_schema(schema)

      assert result["type"] == "object"
      assert result["properties"]["name"] == %{"type" => "string", "description" => "User name"}
      assert result["properties"]["age"] == %{"type" => "integer"}
      assert result["properties"]["active"] == %{"type" => "boolean"}
      assert result["required"] == ["name"]
    end

    test "converts enum types" do
      schema = [status: [type: {:in, [:active, :inactive]}]]
      result = SchemaAdapter.to_json_schema(schema)

      assert result["properties"]["status"] == %{
               "type" => "string",
               "enum" => ["active", "inactive"]
             }
    end

    test "converts list types" do
      schema = [tags: [type: {:list, :string}]]
      result = SchemaAdapter.to_json_schema(schema)

      assert result["properties"]["tags"] == %{
               "type" => "array",
               "items" => %{"type" => "string"}
             }
    end
  end

  describe "to_json_schema/1 with JSONSpec maps" do
    test "passes through JSON Schema maps" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"}
        },
        "required" => ["name"]
      }

      assert SchemaAdapter.to_json_schema(schema) == schema
    end
  end

  describe "validate/2 with NimbleOptions" do
    test "validates and returns atom-keyed map" do
      schema = [
        name: [type: :string, required: true],
        age: [type: :integer, default: 0]
      ]

      assert {:ok, result} = SchemaAdapter.validate(schema, %{"name" => "Alice"})
      assert result == %{name: "Alice", age: 0}
    end
  end

  describe "validate/2 with JSON Schema" do
    test "checks required fields" do
      schema = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string"}},
        "required" => ["name"]
      }

      assert {:error, _} = SchemaAdapter.validate(schema, %{})
      assert {:ok, _} = SchemaAdapter.validate(schema, %{"name" => "Alice"})
    end
  end
end
