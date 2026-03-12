defmodule LiveRender.Catalog.Builder do
  @moduledoc false

  @doc """
  Builds a system prompt from component and action definitions.

  ## Options

    * `:format` — a module implementing `LiveRender.Format`
      (default: `LiveRender.Format.JSONPatch`)
    * `:mode` — legacy shorthand: `:patch` or `:object`
      (overridden by `:format` if both are given)
    * `:custom_rules` — list of additional rule strings for the prompt
  """
  @spec build(%{String.t() => module()}, [{atom(), String.t()}], keyword()) :: String.t()
  def build(component_map, actions, opts \\ []) do
    format = resolve_format(opts)
    format.prompt(component_map, actions, opts)
  end

  @doc """
  Builds a JSON Schema describing the full spec format.
  """
  @spec spec_json_schema(%{String.t() => module()}) :: map()
  def spec_json_schema(component_map) do
    type_enum = Map.keys(component_map)

    %{
      "type" => "object",
      "properties" => %{
        "root" => %{"type" => "string"},
        "state" => %{"type" => "object"},
        "elements" => %{
          "type" => "object",
          "additionalProperties" => %{
            "type" => "object",
            "properties" => %{
              "type" => %{"type" => "string", "enum" => type_enum},
              "props" => %{"type" => "object"},
              "children" => %{"type" => "array", "items" => %{"type" => "string"}},
              "visible" => %{},
              "on" => %{"type" => "object"}
            },
            "required" => ["type", "props", "children"]
          }
        }
      },
      "required" => ["root", "elements"]
    }
  end

  defp resolve_format(opts) do
    case Keyword.get(opts, :format) do
      nil -> mode_to_format(Keyword.get(opts, :mode, :patch))
      format when is_atom(format) -> format
    end
  end

  defp mode_to_format(:patch), do: LiveRender.Format.JSONPatch
  defp mode_to_format(:object), do: LiveRender.Format.JSONObject
  defp mode_to_format(:openui_lang), do: LiveRender.Format.OpenUILang
  defp mode_to_format(:a2ui), do: LiveRender.Format.A2UI
end
