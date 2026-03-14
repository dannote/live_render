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

    test "renders $concat expressions as strings" do
      spec = %{
        "root" => "t1",
        "state" => %{"humidity" => 65},
        "elements" => %{
          "t1" => %{
            "type" => "text",
            "props" => %{
              "content" => %{
                "$concat" => ["Humidity: ", %{"$state" => "/humidity"}, "%"]
              }
            },
            "children" => []
          }
        }
      }

      html = render_spec(spec)
      assert html =~ "Humidity: 65%"
    end

    test "survives $state refs pointing at nil" do
      spec = %{
        "root" => "stack-1",
        "state" => %{"cities" => %{"London" => nil}},
        "elements" => %{
          "stack-1" => %{
            "type" => "stack",
            "props" => %{"direction" => "vertical"},
            "children" => ["text-1", "metric-1"]
          },
          "text-1" => %{
            "type" => "text",
            "props" => %{"content" => %{"$state" => "/cities/London/conditions"}},
            "children" => []
          },
          "metric-1" => %{
            "type" => "metric",
            "props" => %{
              "label" => "Temperature",
              "value" => %{"$state" => "/cities/London/temp"},
              "detail" => "°C"
            },
            "children" => []
          }
        }
      }

      html = render_spec(spec)
      assert html =~ "Temperature"
      assert html =~ "°C"
    end

    test "renders slot components with no children (partial streaming spec)" do
      spec = %{
        "root" => "root",
        "elements" => %{
          "root" => %{"type" => "stack", "props" => %{}}
        }
      }

      html = render_spec(spec)
      assert html =~ "flex"
    end

    test "renders slot components as children arrive incrementally" do
      partial = %{
        "root" => "root",
        "elements" => %{
          "root" => %{"type" => "card", "props" => %{"title" => "Weather"}, "children" => ["h1"]},
          "h1" => %{"type" => "heading", "props" => %{"text" => "Hello"}}
        }
      }

      html = render_spec(partial)
      assert html =~ "Weather"
      assert html =~ "Hello"

      with_more =
        put_in(partial["elements"]["m1"], %{
          "type" => "metric",
          "props" => %{"label" => "Temp", "value" => "72°F"}
        })

      with_more = put_in(with_more["elements"]["root"]["children"], ["h1", "m1"])

      html2 = render_spec(with_more)
      assert html2 =~ "72°F"
    end

    test "renders table with nil $state data without crashing" do
      spec = %{
        "root" => "t",
        "state" => %{},
        "elements" => %{
          "t" => %{
            "type" => "table",
            "props" => %{
              "columns" => [%{"key" => "name", "label" => "Name"}],
              "data" => %{"$state" => "/items"}
            }
          }
        }
      }

      html = render_spec(spec)
      assert html =~ "No data"
    end

    test "survives spec with non-map elements" do
      spec = %{"root" => "main", "elements" => "main"}

      html = render_spec(spec)
      assert html =~ "<div"
      refute html =~ "main"
    end

    test "survives spec with nil elements" do
      spec = %{"root" => "main", "elements" => nil}

      html = render_spec(spec)
      assert html =~ "<div"
    end

    test "renders tabs with nil tabs prop (streaming partial element)" do
      spec = %{
        "root" => "t",
        "elements" => %{
          "t" => %{"type" => "tabs", "props" => %{}, "children" => []}
        }
      }

      html = render_spec(spec, streaming: true)
      assert html =~ "<div"
    end

    test "renders tabs with missing props entirely" do
      spec = %{
        "root" => "t",
        "elements" => %{
          "t" => %{"type" => "tabs", "children" => []}
        }
      }

      html = render_spec(spec, streaming: true)
      assert html =~ "<div"
    end

    test "survives spec with string element value (YAML incremental parse)" do
      spec = %{"root" => "main", "elements" => %{"main" => "type"}}

      html = render_spec(spec)
      assert html =~ "<div"
    end

    test "survives spec with nil element value" do
      spec = %{"root" => "main", "elements" => %{"main" => nil}}

      html = render_spec(spec)
      assert html =~ "<div"
    end

    test "falls back to default when prop value is invalid for enum type" do
      spec = %{
        "root" => "h",
        "elements" => %{
          "h" => %{
            "type" => "heading",
            "props" => %{"text" => "Title", "level" => 1},
            "children" => []
          }
        }
      }

      html = render_spec(spec)
      assert html =~ "Title"
      assert html =~ "<h2"
    end

    test "renders grid with no children" do
      spec = %{
        "root" => "g",
        "elements" => %{
          "g" => %{"type" => "grid", "props" => %{"columns" => 3}}
        }
      }

      html = render_spec(spec)
      assert html =~ "grid"
    end

    test "renders every intermediate YAML streaming spec without crashing" do
      alias LiveRender.Format.YAML

      yaml_chunks = [
        "```spec\n",
        "root: main\n",
        "elements:\n",
        "  main:\n",
        "    type: stack\n",
        "    props: {}\n",
        "    children:\n",
        "      - heading\n",
        "      - metric-1\n",
        "  heading:\n",
        "    type: heading\n",
        "    props:\n",
        "      text: Dashboard\n",
        "    children: []\n",
        "  metric-1:\n",
        "    type: metric\n",
        "    props:\n",
        "      label: Users\n",
        "      value: \"1,234\"\n",
        "    children: []\n",
        "```\n"
      ]

      state = YAML.stream_init()

      {_final_state, all_specs} =
        Enum.reduce(yaml_chunks, {state, []}, fn chunk, {st, specs} ->
          {st, events} = YAML.stream_push(st, chunk)

          new_specs =
            for {:spec, spec} <- events do
              html = render_spec(spec, streaming: true)
              assert is_binary(html), "render_spec crashed on: #{inspect(spec)}"
              spec
            end

          {st, specs ++ new_specs}
        end)

      assert all_specs != []
      last_spec = List.last(all_specs)
      assert last_spec["root"] == "main"
      assert last_spec["elements"]["heading"]["props"]["text"] == "Dashboard"

      final_html = render_spec(last_spec)
      assert final_html =~ "Dashboard"
      assert final_html =~ "Users"
      assert final_html =~ "1,234"
    end

    test "renders every intermediate JSONPatch streaming spec without crashing" do
      alias LiveRender.Format.JSONPatch

      patches = [
        "```spec\n",
        ~s|{"op":"add","path":"/root","value":"main"}\n|,
        ~s|{"op":"add","path":"/elements/main","value":{"type":"stack","props":{},"children":["h1"]}}\n|,
        ~s|{"op":"add","path":"/elements/h1","value":{"type":"heading","props":{"text":"Hello"},"children":[]}}\n|,
        "```\n"
      ]

      state = JSONPatch.stream_init()

      {_final_state, all_specs} =
        Enum.reduce(patches, {state, []}, fn chunk, {st, specs} ->
          {st, events} = JSONPatch.stream_push(st, chunk)

          new_specs =
            for {:spec, spec} <- events do
              html = render_spec(spec, streaming: true)
              assert is_binary(html), "render_spec crashed on: #{inspect(spec)}"
              spec
            end

          {st, specs ++ new_specs}
        end)

      assert all_specs != []
      final_html = render_spec(List.last(all_specs))
      assert final_html =~ "Hello"
    end

    test "renders every intermediate YAML spec even with token-level chunks" do
      alias LiveRender.Format.YAML

      # Simulate LLM token-by-token streaming (small chunks that create
      # intermediate parse states like %{"main" => "type"})
      yaml = """
      root: main
      elements:
        main:
          type: stack
          props: {}
          children:
            - heading
        heading:
          type: heading
          props:
            text: Hello
          children: []
      """

      state = YAML.stream_init()
      {state, _} = YAML.stream_push(state, "```spec\n")

      # Feed character by character
      {final_state, _} =
        yaml
        |> String.graphemes()
        |> Enum.reduce({state, []}, fn char, {st, specs} ->
          {st, events} = YAML.stream_push(st, char)

          new_specs =
            for {:spec, spec} <- events do
              try do
                html = render_spec(spec, streaming: true)
                assert is_binary(html)
              rescue
                e ->
                  flunk(
                    "render_spec crashed on: #{inspect(spec, pretty: true)}\n#{Exception.message(e)}"
                  )
              end

              spec
            end

          {st, specs ++ new_specs}
        end)

      {_final, flush_events} = YAML.stream_flush(final_state)

      for {:spec, spec} <- flush_events do
        html = render_spec(spec, streaming: true)
        assert is_binary(html), "render_spec crashed on flush: #{inspect(spec)}"
      end
    end

    test "renders full weather comparison spec without crashing" do
      spec = %{
        "root" => "root",
        "state" => %{
          "cities" => %{
            "New York" => %{"temp" => 72, "condition" => "Sunny", "humidity" => 65, "wind" => 8},
            "London" => %{"temp" => 15, "condition" => "Rain", "humidity" => 80, "wind" => 12}
          }
        },
        "elements" => %{
          "root" => %{
            "type" => "stack",
            "props" => %{"direction" => "vertical"},
            "children" => ["heading", "grid"]
          },
          "heading" => %{
            "type" => "heading",
            "props" => %{"text" => "Weather Comparison", "level" => "h2"},
            "children" => []
          },
          "grid" => %{
            "type" => "grid",
            "props" => %{"columns" => 2},
            "children" => ["ny-card", "london-card"]
          },
          "ny-card" => %{
            "type" => "card",
            "props" => %{"title" => "New York"},
            "children" => ["ny-temp", "ny-humidity"]
          },
          "ny-temp" => %{
            "type" => "metric",
            "props" => %{
              "label" => "Temperature",
              "value" => %{"$state" => "/cities/New York/temp"},
              "detail" => "°F"
            },
            "children" => []
          },
          "ny-humidity" => %{
            "type" => "text",
            "props" => %{
              "content" => %{
                "$concat" => ["Humidity: ", %{"$state" => "/cities/New York/humidity"}, "%"]
              }
            },
            "children" => []
          },
          "london-card" => %{
            "type" => "card",
            "props" => %{"title" => "London"},
            "children" => ["london-temp", "london-humidity"]
          },
          "london-temp" => %{
            "type" => "metric",
            "props" => %{
              "label" => "Temperature",
              "value" => %{"$state" => "/cities/London/temp"},
              "detail" => "°C"
            },
            "children" => []
          },
          "london-humidity" => %{
            "type" => "text",
            "props" => %{
              "content" => %{
                "$concat" => ["Humidity: ", %{"$state" => "/cities/London/humidity"}, "%"]
              }
            },
            "children" => []
          }
        }
      }

      html = render_spec(spec)
      assert html =~ "Weather Comparison"
      assert html =~ "New York"
      assert html =~ "London"
      assert html =~ "Humidity: 65%"
      assert html =~ "Humidity: 80%"
    end
  end
end
