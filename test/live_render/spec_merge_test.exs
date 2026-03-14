defmodule LiveRender.SpecMergeTest do
  use ExUnit.Case, async: true

  alias LiveRender.SpecMerge

  doctest LiveRender.SpecMerge

  describe "merge/2" do
    test "adds new keys" do
      assert SpecMerge.merge(%{"a" => 1}, %{"b" => 2}) == %{"a" => 1, "b" => 2}
    end

    test "replaces existing scalar values" do
      assert SpecMerge.merge(%{"a" => 1}, %{"a" => 2}) == %{"a" => 2}
    end

    test "deletes keys set to nil" do
      assert SpecMerge.merge(%{"a" => 1, "b" => 2}, %{"b" => nil}) == %{"a" => 1}
    end

    test "deleting a nonexistent key is a no-op" do
      assert SpecMerge.merge(%{"a" => 1}, %{"z" => nil}) == %{"a" => 1}
    end

    test "recurses into nested maps" do
      base = %{"nested" => %{"x" => 1, "y" => 2}}
      patch = %{"nested" => %{"y" => 3, "z" => 4}}

      assert SpecMerge.merge(base, patch) == %{"nested" => %{"x" => 1, "y" => 3, "z" => 4}}
    end

    test "replaces arrays atomically" do
      base = %{"items" => [1, 2, 3]}
      patch = %{"items" => [4, 5]}

      assert SpecMerge.merge(base, patch) == %{"items" => [4, 5]}
    end

    test "replaces non-map base value with map patch" do
      base = %{"a" => "string"}
      patch = %{"a" => %{"nested" => true}}

      assert SpecMerge.merge(base, patch) == %{"a" => %{"nested" => true}}
    end

    test "replaces map base value with scalar patch" do
      base = %{"a" => %{"nested" => true}}
      patch = %{"a" => "string"}

      assert SpecMerge.merge(base, patch) == %{"a" => "string"}
    end

    test "empty patch returns base unchanged" do
      base = %{"a" => 1}
      assert SpecMerge.merge(base, %{}) == base
    end

    test "empty base gets all patch keys" do
      assert SpecMerge.merge(%{}, %{"a" => 1}) == %{"a" => 1}
    end

    test "deeply nested merge with deletion" do
      base = %{
        "elements" => %{
          "card" => %{"type" => "card", "props" => %{"title" => "Old"}, "children" => ["a"]},
          "old-widget" => %{"type" => "text", "props" => %{}, "children" => []}
        }
      }

      patch = %{
        "elements" => %{
          "card" => %{"props" => %{"title" => "New"}},
          "old-widget" => nil,
          "new-chart" => %{"type" => "chart", "props" => %{}, "children" => []}
        }
      }

      result = SpecMerge.merge(base, patch)

      assert result["elements"]["card"]["type"] == "card"
      assert result["elements"]["card"]["props"]["title"] == "New"
      assert result["elements"]["card"]["children"] == ["a"]
      refute Map.has_key?(result["elements"], "old-widget")
      assert result["elements"]["new-chart"]["type"] == "chart"
    end

    test "real-world spec edit: update title and add element" do
      base = %{
        "root" => "main",
        "elements" => %{
          "main" => %{
            "type" => "stack",
            "props" => %{},
            "children" => ["heading"]
          },
          "heading" => %{
            "type" => "heading",
            "props" => %{"text" => "Dashboard"},
            "children" => []
          }
        },
        "state" => %{}
      }

      patch = %{
        "elements" => %{
          "heading" => %{"props" => %{"text" => "Updated Dashboard"}},
          "metric-1" => %{
            "type" => "metric",
            "props" => %{"label" => "Users", "value" => "42"},
            "children" => []
          },
          "main" => %{"children" => ["heading", "metric-1"]}
        }
      }

      result = SpecMerge.merge(base, patch)

      assert result["root"] == "main"
      assert result["elements"]["heading"]["props"]["text"] == "Updated Dashboard"
      assert result["elements"]["heading"]["type"] == "heading"
      assert result["elements"]["metric-1"]["type"] == "metric"
      assert result["elements"]["main"]["children"] == ["heading", "metric-1"]
    end
  end
end
