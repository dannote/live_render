defmodule LiveRender.RendererTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  defp render_spec(spec, opts \\ []) do
    catalog = Keyword.get(opts, :catalog, LiveRender.StandardCatalog)
    streaming = Keyword.get(opts, :streaming, false)

    assigns = %{spec: spec, catalog: catalog, streaming: streaming}

    rendered_to_string(~H"""
    <LiveRender.render spec={@spec} catalog={@catalog} streaming={@streaming} />
    """)
  end

  describe "render/1" do
    test "renders a simple heading" do
      spec = %{
        "root" => "h1",
        "elements" => %{
          "h1" => %{
            "type" => "heading",
            "props" => %{"text" => "Hello World"},
            "children" => []
          }
        }
      }

      html = render_spec(spec)
      assert html =~ "Hello World"
    end

    test "renders nested card with metric" do
      spec = %{
        "root" => "card-1",
        "elements" => %{
          "card-1" => %{
            "type" => "card",
            "props" => %{"title" => "Weather"},
            "children" => ["metric-1"]
          },
          "metric-1" => %{
            "type" => "metric",
            "props" => %{"label" => "Temperature", "value" => "72°F"},
            "children" => []
          }
        }
      }

      html = render_spec(spec)
      assert html =~ "Weather"
      assert html =~ "Temperature"
      assert html =~ "72°F"
    end

    test "resolves $state in props" do
      spec = %{
        "root" => "m1",
        "state" => %{"temp" => "72°F"},
        "elements" => %{
          "m1" => %{
            "type" => "metric",
            "props" => %{"label" => "Temp", "value" => %{"$state" => "/temp"}},
            "children" => []
          }
        }
      }

      html = render_spec(spec)
      assert html =~ "72°F"
    end

    test "hides elements when visibility is false" do
      spec = %{
        "root" => "t1",
        "state" => %{"show" => false},
        "elements" => %{
          "t1" => %{
            "type" => "text",
            "props" => %{"content" => "Secret"},
            "visible" => %{"$state" => "/show"},
            "children" => []
          }
        }
      }

      html = render_spec(spec)
      refute html =~ "Secret"
    end

    test "shows elements when visibility is true" do
      spec = %{
        "root" => "t1",
        "state" => %{"show" => true},
        "elements" => %{
          "t1" => %{
            "type" => "text",
            "props" => %{"content" => "Visible"},
            "visible" => %{"$state" => "/show"},
            "children" => []
          }
        }
      }

      html = render_spec(spec)
      assert html =~ "Visible"
    end

    test "handles nil root gracefully" do
      html = render_spec(%{"elements" => %{}})
      assert html =~ "<div"
    end

    test "skips unknown component types" do
      spec = %{
        "root" => "x",
        "elements" => %{
          "x" => %{
            "type" => "unknown_widget",
            "props" => %{},
            "children" => []
          }
        }
      }

      html = render_spec(spec)
      assert is_binary(html)
    end

    test "renders multiple children in order" do
      spec = %{
        "root" => "stack-1",
        "elements" => %{
          "stack-1" => %{
            "type" => "stack",
            "props" => %{},
            "children" => ["t1", "t2"]
          },
          "t1" => %{
            "type" => "text",
            "props" => %{"content" => "First"},
            "children" => []
          },
          "t2" => %{
            "type" => "text",
            "props" => %{"content" => "Second"},
            "children" => []
          }
        }
      }

      html = render_spec(spec)
      assert html =~ "First"
      assert html =~ "Second"
    end

    test "renders callout component" do
      spec = %{
        "root" => "c1",
        "elements" => %{
          "c1" => %{
            "type" => "callout",
            "props" => %{"type" => "tip", "title" => "Pro tip", "content" => "Use LiveRender"},
            "children" => []
          }
        }
      }

      html = render_spec(spec)
      assert html =~ "Pro tip"
      assert html =~ "Use LiveRender"
    end

    test "renders badge component" do
      spec = %{
        "root" => "b1",
        "elements" => %{
          "b1" => %{
            "type" => "badge",
            "props" => %{"text" => "Active", "variant" => "success"},
            "children" => []
          }
        }
      }

      html = render_spec(spec)
      assert html =~ "Active"
      assert html =~ "green"
    end
  end
end
