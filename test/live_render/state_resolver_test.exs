defmodule LiveRender.StateResolverTest do
  use ExUnit.Case, async: true

  alias LiveRender.StateResolver

  describe "get_in_path/2" do
    test "gets nested value" do
      state = %{"weather" => %{"temp" => 72}}
      assert StateResolver.get_in_path(state, "/weather/temp") == 72
    end

    test "returns nil for missing path" do
      assert StateResolver.get_in_path(%{}, "/missing/path") == nil
    end

    test "gets top-level value" do
      assert StateResolver.get_in_path(%{"name" => "Alice"}, "/name") == "Alice"
    end
  end

  describe "put_in_path/3" do
    test "sets nested value" do
      state = %{"a" => %{"b" => 1}}
      assert StateResolver.put_in_path(state, "/a/b", 2) == %{"a" => %{"b" => 2}}
    end

    test "creates intermediate maps" do
      assert StateResolver.put_in_path(%{}, "/a/b/c", 42) == %{"a" => %{"b" => %{"c" => 42}}}
    end
  end

  describe "resolve/2" do
    test "resolves $state reference" do
      state = %{"temp" => 72}
      assert StateResolver.resolve(%{"$state" => "/temp"}, state) == 72
    end

    test "resolves $bindState reference" do
      state = %{"answer" => "yes"}
      assert StateResolver.resolve(%{"$bindState" => "/answer"}, state) == "yes"
    end

    test "resolves $cond/$then/$else with truthy condition" do
      state = %{"flag" => true}

      result =
        StateResolver.resolve(
          %{"$cond" => %{"$state" => "/flag"}, "$then" => "yes", "$else" => "no"},
          state
        )

      assert result == "yes"
    end

    test "resolves $cond/$then/$else with falsy condition" do
      state = %{"flag" => false}

      result =
        StateResolver.resolve(
          %{"$cond" => %{"$state" => "/flag"}, "$then" => "yes", "$else" => "no"},
          state
        )

      assert result == "no"
    end

    test "resolves $cond with eq check" do
      state = %{"status" => "active"}

      result =
        StateResolver.resolve(
          %{
            "$cond" => %{"$state" => "/status", "eq" => "active"},
            "$then" => "Running",
            "$else" => "Stopped"
          },
          state
        )

      assert result == "Running"
    end

    test "resolves $template" do
      state = %{"user" => %{"name" => "Alice"}}

      result =
        StateResolver.resolve(%{"$template" => "Hello, ${/user/name}!"}, state)

      assert result == "Hello, Alice!"
    end

    test "resolves nested maps recursively" do
      state = %{"color" => "blue", "size" => "large"}

      result =
        StateResolver.resolve(
          %{"bg" => %{"$state" => "/color"}, "sz" => %{"$state" => "/size"}},
          state
        )

      assert result == %{"bg" => "blue", "sz" => "large"}
    end

    test "resolves lists" do
      state = %{"a" => 1, "b" => 2}

      result =
        StateResolver.resolve(
          [%{"$state" => "/a"}, %{"$state" => "/b"}],
          state
        )

      assert result == [1, 2]
    end

    test "passes through plain values" do
      assert StateResolver.resolve("hello", %{}) == "hello"
      assert StateResolver.resolve(42, %{}) == 42
      assert StateResolver.resolve(nil, %{}) == nil
    end
  end

  describe "extract_bindings/1" do
    test "extracts $bindState paths" do
      props = %{
        "label" => "Name",
        "value" => %{"$bindState" => "/form/name"},
        "other" => %{"$state" => "/x"}
      }

      assert StateResolver.extract_bindings(props) == %{"value" => "/form/name"}
    end

    test "returns empty map when no bindings" do
      assert StateResolver.extract_bindings(%{"label" => "hi"}) == %{}
    end
  end
end
