defmodule LiveRender.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/dannote/live_render"

  def project do
    [
      app: :live_render,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      name: "LiveRender",
      description: "Server-driven generative UI for Phoenix LiveView",
      source_url: @source_url,
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_html, "~> 4.0"},
      {:jason, "~> 1.4"},
      {:json_spec, "~> 1.1", optional: true},
      {:nimble_options, "~> 1.0", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "LiveRender",
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
