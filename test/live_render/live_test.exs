defmodule LiveRender.LiveTest do
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [assign: 2]

  describe "init_live_render/1" do
    test "sets default assigns" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
      socket = LiveRender.Live.init_live_render(socket)

      assert socket.assigns.lr_spec == %{}
      assert socket.assigns.lr_text == ""
      assert socket.assigns.lr_streaming? == false
    end
  end

  describe "start_live_render/1" do
    test "resets assigns for new generation" do
      socket = %Phoenix.LiveView.Socket{
        assigns:
          assign(%{__changed__: %{}}, %{
            lr_spec: %{"root" => "old"},
            lr_text: "old text",
            lr_streaming?: false
          })
      }

      socket = LiveRender.Live.start_live_render(socket)

      assert socket.assigns.lr_spec == %{}
      assert socket.assigns.lr_text == ""
      assert socket.assigns.lr_streaming? == true
    end
  end
end
