defmodule LiveRender.ToolTest do
  use ExUnit.Case, async: true

  describe "new/1" do
    test "creates a tool via ReqLLM.Tool" do
      assert {:ok, tool} =
               LiveRender.Tool.new(
                 name: "test_tool",
                 description: "A test tool",
                 parameter_schema: [
                   query: [type: :string, required: true, doc: "Search query"]
                 ],
                 callback: fn args -> {:ok, "result for #{args[:query]}"} end
               )

      assert tool.name == "test_tool"
      assert tool.description == "A test tool"
    end

    test "new! raises on invalid opts" do
      assert_raise ReqLLM.Error.Validation.Error, fn ->
        LiveRender.Tool.new!(name: 123)
      end
    end
  end
end
