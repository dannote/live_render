defmodule LiveRender.JSONRepairTest do
  use ExUnit.Case, async: true

  alias LiveRender.JSONRepair

  describe "repair/1" do
    test "complete JSON passes through unchanged" do
      json = ~s({"root": "main", "elements": {}})
      assert Jason.decode!(JSONRepair.repair(json)) == %{"root" => "main", "elements" => %{}}
    end

    test "closes unclosed string" do
      assert {:ok, %{"key" => "val"}} = Jason.decode(JSONRepair.repair(~s({"key": "val)))
    end

    test "closes unclosed object" do
      assert {:ok, %{"a" => 1}} = Jason.decode(JSONRepair.repair(~s({"a": 1)))
    end

    test "closes unclosed array" do
      assert {:ok, %{"a" => [1, 2]}} = Jason.decode(JSONRepair.repair(~s({"a": [1, 2)))
    end

    test "handles trailing comma" do
      assert {:ok, %{"a" => 1}} = Jason.decode(JSONRepair.repair(~s({"a": 1,)))
    end

    test "handles trailing colon by appending null" do
      assert {:ok, %{"a" => 1, "b" => nil}} = Jason.decode(JSONRepair.repair(~s({"a": 1, "b":)))
    end

    test "handles dangling value position" do
      assert {:ok, %{"root" => nil}} = Jason.decode(JSONRepair.repair(~s({"root": )))
    end

    test "handles nested incomplete objects" do
      repaired = JSONRepair.repair(~s({"a": {"b": {"c": "d"))
      assert {:ok, %{"a" => %{"b" => %{"c" => "d"}}}} = Jason.decode(repaired)
    end

    test "handles mixed arrays and objects" do
      repaired = JSONRepair.repair(~s({"items": [{"name": "x"}, {"name": "y"))
      assert {:ok, decoded} = Jason.decode(repaired)
      assert length(decoded["items"]) == 2
    end

    test "handles string with escaped quotes" do
      repaired = JSONRepair.repair(~s({"msg": "say \\"hello))
      assert {:ok, %{"msg" => "say \"hello"}} = Jason.decode(repaired)
    end

    test "empty string returns valid JSON-like structure" do
      repaired = JSONRepair.repair("")
      assert is_binary(repaired)
    end
  end
end
