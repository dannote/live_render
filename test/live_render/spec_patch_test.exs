defmodule LiveRender.SpecPatchTest do
  use ExUnit.Case, async: true

  alias LiveRender.SpecPatch

  describe "apply/2" do
    test "add root" do
      spec = %{"elements" => %{}}
      result = SpecPatch.apply(spec, %{"op" => "add", "path" => "/root", "value" => "main"})
      assert result["root"] == "main"
    end

    test "add element" do
      spec = %{"root" => "main", "elements" => %{}}
      element = %{"type" => "card", "props" => %{"title" => "Hello"}, "children" => []}

      result =
        SpecPatch.apply(spec, %{
          "op" => "add",
          "path" => "/elements/card-1",
          "value" => element
        })

      assert result["elements"]["card-1"] == element
    end

    test "add state" do
      spec = %{"root" => "main", "elements" => %{}, "state" => %{}}

      result =
        SpecPatch.apply(spec, %{
          "op" => "add",
          "path" => "/state/weather",
          "value" => %{"temp" => 72}
        })

      assert result["state"]["weather"] == %{"temp" => 72}
    end

    test "add nested state" do
      spec = %{"state" => %{"cities" => %{}}}

      result =
        SpecPatch.apply(spec, %{
          "op" => "add",
          "path" => "/state/cities/nyc",
          "value" => %{"temp" => 72}
        })

      assert result["state"]["cities"]["nyc"] == %{"temp" => 72}
    end

    test "replace existing element" do
      spec = %{
        "elements" => %{
          "card-1" => %{"type" => "card", "props" => %{"title" => "Old"}, "children" => []}
        }
      }

      result =
        SpecPatch.apply(spec, %{
          "op" => "replace",
          "path" => "/elements/card-1",
          "value" => %{"type" => "card", "props" => %{"title" => "New"}, "children" => []}
        })

      assert result["elements"]["card-1"]["props"]["title"] == "New"
    end

    test "remove element" do
      spec = %{"elements" => %{"a" => %{}, "b" => %{}}}
      result = SpecPatch.apply(spec, %{"op" => "remove", "path" => "/elements/a"})
      refute Map.has_key?(result["elements"], "a")
      assert Map.has_key?(result["elements"], "b")
    end

    test "unknown op is ignored" do
      spec = %{"root" => "x"}
      assert SpecPatch.apply(spec, %{"op" => "test", "path" => "/root", "value" => "x"}) == spec
    end

    test "append to array with -" do
      spec = %{"state" => %{"items" => []}}

      result =
        SpecPatch.apply(spec, %{
          "op" => "add",
          "path" => "/state/items/-",
          "value" => %{"id" => "1", "name" => "First"}
        })

      assert result["state"]["items"] == [%{"id" => "1", "name" => "First"}]

      result =
        SpecPatch.apply(result, %{
          "op" => "add",
          "path" => "/state/items/-",
          "value" => %{"id" => "2", "name" => "Second"}
        })

      assert length(result["state"]["items"]) == 2
      assert Enum.at(result["state"]["items"], 1) == %{"id" => "2", "name" => "Second"}
    end

    test "replace nested value in array element by index" do
      spec = %{"state" => %{"items" => [%{"name" => "old"}, %{"name" => "keep"}]}}

      result =
        SpecPatch.apply(spec, %{
          "op" => "replace",
          "path" => "/state/items/0/name",
          "value" => "new"
        })

      assert Enum.at(result["state"]["items"], 0)["name"] == "new"
      assert Enum.at(result["state"]["items"], 1)["name"] == "keep"
    end

    test "add at numeric index in array" do
      spec = %{"state" => %{"items" => ["a", "b", "c"]}}

      result =
        SpecPatch.apply(spec, %{
          "op" => "add",
          "path" => "/state/items/1",
          "value" => "inserted"
        })

      assert result["state"]["items"] == ["a", "inserted", "b", "c"]
    end
  end

  describe "parse_and_apply/2" do
    test "parses valid patch line" do
      spec = %{"elements" => %{}}
      line = ~s({"op":"add","path":"/root","value":"main"})
      assert {:ok, new_spec} = SpecPatch.parse_and_apply(spec, line)
      assert new_spec["root"] == "main"
    end

    test "skips empty lines" do
      assert :skip = SpecPatch.parse_and_apply(%{}, "")
      assert :skip = SpecPatch.parse_and_apply(%{}, "   ")
    end

    test "skips comment lines" do
      assert :skip = SpecPatch.parse_and_apply(%{}, "// this is a comment")
    end

    test "skips invalid JSON" do
      assert :skip = SpecPatch.parse_and_apply(%{}, "not json")
    end

    test "skips JSON without op field" do
      assert :skip = SpecPatch.parse_and_apply(%{}, ~s({"foo": "bar"}))
    end

    test "progressive build of a full spec" do
      patches = [
        ~s({"op":"add","path":"/root","value":"root"}),
        ~s({"op":"add","path":"/elements/root","value":{"type":"stack","props":{},"children":["h1","metric"]}}),
        ~s({"op":"add","path":"/elements/h1","value":{"type":"heading","props":{"text":"Dashboard"},"children":[]}}),
        ~s({"op":"add","path":"/elements/metric","value":{"type":"metric","props":{"label":"Users","value":{"$state":"/users"}},"children":[]}}),
        ~s({"op":"add","path":"/state","value":{}}),
        ~s({"op":"add","path":"/state/users","value":"1,234"})
      ]

      {specs, _} =
        Enum.map_reduce(patches, %{"elements" => %{}, "state" => %{}}, fn line, spec ->
          {:ok, new_spec} = SpecPatch.parse_and_apply(spec, line)
          {new_spec, new_spec}
        end)

      # After first patch: has root
      assert Enum.at(specs, 0)["root"] == "root"
      # After second: has 1 element
      assert map_size(Enum.at(specs, 1)["elements"]) == 1
      # After fourth: has 3 elements
      assert map_size(Enum.at(specs, 3)["elements"]) == 3
      # After sixth: has state
      assert Enum.at(specs, 5)["state"]["users"] == "1,234"

      final = List.last(specs)
      assert final["root"] == "root"
      assert final["elements"]["root"]["type"] == "stack"
      assert final["elements"]["h1"]["props"]["text"] == "Dashboard"
      assert final["state"]["users"] == "1,234"
    end
  end
end
